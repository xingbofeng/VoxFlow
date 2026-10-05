import Foundation
import MLX
import MLXFast
import MLXLMCommon
import MLXNN

final class TextAttention: Module {
    let numHeads: Int
    let numKVHeads: Int
    let headDim: Int
    let scale: Float
    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear
    @ModuleInfo(key: "q_norm") var qNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: RMSNorm
    let rope: RoPE

    init(_ cfg: Qwen3ASRTextConfig) {
        numHeads = cfg.numAttentionHeads
        numKVHeads = cfg.numKeyValueHeads
        headDim = cfg.headDim
        scale = pow(Float(cfg.headDim), -0.5)
        _qProj.wrappedValue = Linear(cfg.hiddenSize, numHeads * headDim, bias: false)
        _kProj.wrappedValue = Linear(cfg.hiddenSize, numKVHeads * headDim, bias: false)
        _vProj.wrappedValue = Linear(cfg.hiddenSize, numKVHeads * headDim, bias: false)
        _oProj.wrappedValue = Linear(numHeads * headDim, cfg.hiddenSize, bias: false)
        _qNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: cfg.rmsNormEps)
        _kNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: cfg.rmsNormEps)
        rope = RoPE(dimensions: headDim, traditional: false, base: cfg.ropeTheta)
        super.init()
    }

    func callAsFunction(_ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache?) -> MLXArray {
        let B = x.dim(0), L = x.dim(1)
        var q = qNorm(qProj(x).reshaped(B, L, numHeads, headDim)).transposed(0, 2, 1, 3)
        var k = kNorm(kProj(x).reshaped(B, L, numKVHeads, headDim)).transposed(0, 2, 1, 3)
        let v = vProj(x).reshaped(B, L, numKVHeads, headDim).transposed(0, 2, 1, 3)
        let offset = cache?.offset ?? 0
        q = rope(q, offset: offset)
        k = rope(k, offset: offset)
        let o = attentionWithCacheUpdate(queries: q, keys: k, values: v, cache: cache, scale: scale, mask: mask)
        return oProj(o.transposed(0, 2, 1, 3).reshaped(B, L, numHeads * headDim))
    }
}

final class TextMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear
    init(_ cfg: Qwen3ASRTextConfig) {
        _gateProj.wrappedValue = Linear(cfg.hiddenSize, cfg.intermediateSize, bias: false)
        _upProj.wrappedValue = Linear(cfg.hiddenSize, cfg.intermediateSize, bias: false)
        _downProj.wrappedValue = Linear(cfg.intermediateSize, cfg.hiddenSize, bias: false)
        super.init()
    }
    func callAsFunction(_ x: MLXArray) -> MLXArray { downProj(silu(gateProj(x)) * upProj(x)) }
}

final class TextDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: TextAttention
    @ModuleInfo(key: "mlp") var mlp: TextMLP
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm
    init(_ cfg: Qwen3ASRTextConfig) {
        _selfAttn.wrappedValue = TextAttention(cfg)
        _mlp.wrappedValue = TextMLP(cfg)
        _inputLayerNorm.wrappedValue = RMSNorm(dimensions: cfg.hiddenSize, eps: cfg.rmsNormEps)
        _postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: cfg.hiddenSize, eps: cfg.rmsNormEps)
        super.init()
    }
    func callAsFunction(_ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache?) -> MLXArray {
        var h = x + selfAttn(inputLayerNorm(x), mask: mask, cache: cache)
        h = h + mlp(postAttentionLayerNorm(h))
        return h
    }
}

/// The Qwen3 decoder (`thinker.model`): embeddings → 28 layers → final norm. The caller supplies
/// input EMBEDDINGS (audio features are spliced in before the layers), so `callAsFunction` takes
/// them directly; `embed` exposes the token table for the splice and the tied output head.
public final class Qwen3ASRTextModel: Module {
    public let config: Qwen3ASRTextConfig
    @ModuleInfo(key: "embed_tokens") public var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [TextDecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    public init(_ cfg: Qwen3ASRTextConfig) {
        config = cfg
        _embedTokens.wrappedValue = Embedding(embeddingCount: cfg.vocabSize, dimensions: cfg.hiddenSize)
        _layers.wrappedValue = (0 ..< cfg.numHiddenLayers).map { _ in TextDecoderLayer(cfg) }
        _norm.wrappedValue = RMSNorm(dimensions: cfg.hiddenSize, eps: cfg.rmsNormEps)
        super.init()
    }

    public func newCache() -> [KVCache] { (0 ..< config.numHiddenLayers).map { _ in KVCacheSimple() } }

    public func embed(_ ids: MLXArray) -> MLXArray { embedTokens(ids) }

    /// Hidden states after the final norm for `embeddings: [B, L, hidden]`.
    public func callAsFunction(embeddings: MLXArray, cache: [KVCache]?) -> MLXArray {
        let mask = createAttentionMask(h: embeddings, cache: cache)
        var h = embeddings
        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i])
        }
        return norm(h)
    }
}
