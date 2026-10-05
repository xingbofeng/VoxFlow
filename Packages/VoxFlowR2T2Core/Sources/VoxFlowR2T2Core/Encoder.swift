import Foundation
import MLX
import MLXFast
import MLXNN

/// `SinusoidsPositionEmbedding(length, channels, max_timescale=10000)`: `[sin | cos]` per position.
final class SinusoidalPositions: Module {
    // Underscore-prefixed so MLXNN does not register it as a parameter — it is a constant table,
    // not a weight the checkpoint carries.
    let _table: MLXArray
    init(length: Int, channels: Int, maxTimescale: Float = 10000) {
        precondition(channels % 2 == 0)
        let inc = log(maxTimescale) / Float(channels / 2 - 1)
        let invTimescales = MLX.exp(-inc * MLXArray(0 ..< (channels / 2)).asType(.float32))
        let positions = MLXArray(0 ..< length).asType(.float32).reshaped(-1, 1)
        let scaled = positions * invTimescales.reshaped(1, -1)
        _table = concatenated([MLX.sin(scaled), MLX.cos(scaled)], axis: 1)
        super.init()
    }
    func callAsFunction(_ n: Int) -> MLXArray { _table[0 ..< n] }
}

final class EncoderAttention: Module {
    let numHeads: Int
    let headDim: Int
    let scale: Float
    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    init(_ cfg: Qwen3ASRAudioConfig) {
        numHeads = cfg.encoderAttentionHeads
        headDim = cfg.dModel / cfg.encoderAttentionHeads
        scale = pow(Float(headDim), -0.5)
        _qProj.wrappedValue = Linear(cfg.dModel, cfg.dModel, bias: true)
        _kProj.wrappedValue = Linear(cfg.dModel, cfg.dModel, bias: true)
        _vProj.wrappedValue = Linear(cfg.dModel, cfg.dModel, bias: true)
        _outProj.wrappedValue = Linear(cfg.dModel, cfg.dModel, bias: true)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let B = x.dim(0), L = x.dim(1)
        let q = qProj(x).reshaped(B, L, numHeads, headDim).transposed(0, 2, 1, 3)
        let k = kProj(x).reshaped(B, L, numHeads, headDim).transposed(0, 2, 1, 3)
        let v = vProj(x).reshaped(B, L, numHeads, headDim).transposed(0, 2, 1, 3)
        // Bidirectional inside a block: the block IS the attention window, so no mask.
        let o = MLXFast.scaledDotProductAttention(queries: q, keys: k, values: v, scale: scale, mask: .none)
        return outProj(o.transposed(0, 2, 1, 3).reshaped(B, L, numHeads * headDim))
    }
}

final class EncoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: EncoderAttention
    @ModuleInfo(key: "self_attn_layer_norm") var selfAttnLayerNorm: LayerNorm
    @ModuleInfo(key: "fc1") var fc1: Linear
    @ModuleInfo(key: "fc2") var fc2: Linear
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    init(_ cfg: Qwen3ASRAudioConfig) {
        _selfAttn.wrappedValue = EncoderAttention(cfg)
        _selfAttnLayerNorm.wrappedValue = LayerNorm(dimensions: cfg.dModel)
        _fc1.wrappedValue = Linear(cfg.dModel, cfg.encoderFfnDim)
        _fc2.wrappedValue = Linear(cfg.encoderFfnDim, cfg.dModel)
        _finalLayerNorm.wrappedValue = LayerNorm(dimensions: cfg.dModel)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x + selfAttn(selfAttnLayerNorm(x))
        h = h + fc2(gelu(fc1(finalLayerNorm(h))))
        return h
    }
}

/// The AuT audio encoder (`thinker.audio_tower`): three stride-2 Conv2d over `[mel, frames]`
/// (8× in time, 128 → 16 in frequency) → `conv_out` → sinusoidal positions per 100-frame conv
/// chunk → 24 bidirectional transformer layers over BLOCKS of `n_window_infer` (800) frames →
/// `ln_post` → `proj1` → gelu → `proj2` (1024 → 2048, the decoder width).
///
/// Blocks never attend to each other (the reference builds a block-diagonal `cu_seqlens` mask),
/// so a block's features depend only on its own 8 s of mel. That is what lets the streaming
/// loop cache completed blocks and re-encode only the partial one.
public final class Qwen3ASRAudioEncoder: Module {
    public let config: Qwen3ASRAudioConfig
    @ModuleInfo(key: "conv2d1") var conv2d1: Conv2d
    @ModuleInfo(key: "conv2d2") var conv2d2: Conv2d
    @ModuleInfo(key: "conv2d3") var conv2d3: Conv2d
    @ModuleInfo(key: "conv_out") var convOut: Linear
    @ModuleInfo(key: "layers") var layers: [EncoderLayer]
    @ModuleInfo(key: "ln_post") var lnPost: LayerNorm
    @ModuleInfo(key: "proj1") var proj1: Linear
    @ModuleInfo(key: "proj2") var proj2: Linear
    let positions: SinusoidalPositions

    public init(_ cfg: Qwen3ASRAudioConfig) {
        config = cfg
        let h = cfg.downsampleHiddenSize
        _conv2d1.wrappedValue = Conv2d(inputChannels: 1, outputChannels: h, kernelSize: 3, stride: 2, padding: 1)
        _conv2d2.wrappedValue = Conv2d(inputChannels: h, outputChannels: h, kernelSize: 3, stride: 2, padding: 1)
        _conv2d3.wrappedValue = Conv2d(inputChannels: h, outputChannels: h, kernelSize: 3, stride: 2, padding: 1)
        let freqAfterConv = ((((cfg.numMelBins + 1) / 2) + 1) / 2 + 1) / 2
        _convOut.wrappedValue = Linear(h * freqAfterConv, cfg.dModel, bias: false)
        _layers.wrappedValue = (0 ..< cfg.encoderLayers).map { _ in EncoderLayer(cfg) }
        _lnPost.wrappedValue = LayerNorm(dimensions: cfg.dModel)
        _proj1.wrappedValue = Linear(cfg.dModel, cfg.dModel)
        _proj2.wrappedValue = Linear(cfg.dModel, cfg.outputDim)
        positions = SinusoidalPositions(length: cfg.maxSourcePositions, channels: cfg.dModel)
        super.init()
    }

    /// Conv front-end + positions for ONE block of mel frames `[frames ≤ blockFrames, nMels]`:
    /// returns `[tokens, dModel]` with the per-chunk valid lengths applied.
    private func convBlock(_ mel: MLXArray) -> MLXArray {
        let chunkFrames = config.convChunkFrames
        let frames = mel.dim(0)
        let numChunks = (frames + chunkFrames - 1) / chunkFrames
        var chunks: [MLXArray] = []
        var valid: [Int] = []
        for j in 0 ..< numChunks {
            let start = j * chunkFrames
            let end = min(start + chunkFrames, frames)
            var c = mel[start ..< end].transposed(1, 0)          // [nMels, clen]
            if end - start < chunkFrames {
                c = padded(c, widths: [IntOrPair((0, 0)), IntOrPair((0, chunkFrames - (end - start)))])
            }
            chunks.append(c)
            valid.append(qwen3ASRAudioTokenCount(frames: end - start, chunkFrames: chunkFrames))
        }
        var x = stacked(chunks, axis: 0).expandedDimensions(axis: -1)   // [B, nMels, chunkFrames, 1] (NHWC)
        x = gelu(conv2d1(x))
        x = gelu(conv2d2(x))
        x = gelu(conv2d3(x))
        let f = x.dim(1), t = x.dim(2), c = x.dim(3)
        x = x.transposed(0, 2, 3, 1).reshaped(numChunks, t, c * f)       // [B, t, c·f] — channel-major like the reference
        x = convOut(x)
        x = x + positions(t).expandedDimensions(axis: 0)
        let parts = (0 ..< numChunks).map { x[$0, 0 ..< valid[$0]] }
        return concatenated(parts, axis: 0)
    }

    /// Encodes ONE attention block (`frames ≤ blockFrames`) to decoder-width features `[tokens, outputDim]`.
    public func encodeBlock(_ mel: MLXArray) -> MLXArray {
        precondition(mel.dim(0) <= config.blockFrames, "a block is at most \(config.blockFrames) frames")
        var h = convBlock(mel).expandedDimensions(axis: 0)
        for layer in layers { h = layer(h) }
        h = h.squeezed(axis: 0)
        return proj2(gelu(proj1(lnPost(h))))
    }

    /// Encodes a whole clip `[frames, nMels]` block by block; `[tokens, outputDim]`.
    public func encode(_ mel: MLXArray) -> MLXArray {
        let frames = mel.dim(0)
        var out: [MLXArray] = []
        var start = 0
        while start < frames {
            let end = min(start + config.blockFrames, frames)
            out.append(encodeBlock(mel[start ..< end]))
            start = end
        }
        return concatenated(out, axis: 0)
    }
}
