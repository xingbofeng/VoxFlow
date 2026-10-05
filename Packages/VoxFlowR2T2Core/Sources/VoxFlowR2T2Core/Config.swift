import Foundation
import MLXLMCommon

/// `thinker_config.audio_config` — the AuT encoder (model_type `qwen3_asr_audio_encoder`).
public struct Qwen3ASRAudioConfig: Codable, Sendable {
    public var numMelBins: Int = 128
    public var encoderLayers: Int = 24
    public var encoderAttentionHeads: Int = 16
    public var encoderFfnDim: Int = 4096
    public var dModel: Int = 1024
    public var activationFunction: String = "gelu"
    public var scaleEmbedding: Bool = false
    public var maxSourcePositions: Int = 1500
    public var nWindow: Int = 50
    public var outputDim: Int = 2048
    public var nWindowInfer: Int = 800
    public var convChunksize: Int = 500
    public var downsampleHiddenSize: Int = 480

    enum CodingKeys: String, CodingKey {
        case numMelBins = "num_mel_bins"
        case encoderLayers = "encoder_layers"
        case encoderAttentionHeads = "encoder_attention_heads"
        case encoderFfnDim = "encoder_ffn_dim"
        case dModel = "d_model"
        case activationFunction = "activation_function"
        case scaleEmbedding = "scale_embedding"
        case maxSourcePositions = "max_source_positions"
        case nWindow = "n_window"
        case outputDim = "output_dim"
        case nWindowInfer = "n_window_infer"
        case convChunksize = "conv_chunksize"
        case downsampleHiddenSize = "downsample_hidden_size"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numMelBins = try c.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 128
        encoderLayers = try c.decodeIfPresent(Int.self, forKey: .encoderLayers) ?? 24
        encoderAttentionHeads = try c.decodeIfPresent(Int.self, forKey: .encoderAttentionHeads) ?? 16
        encoderFfnDim = try c.decodeIfPresent(Int.self, forKey: .encoderFfnDim) ?? 4096
        dModel = try c.decodeIfPresent(Int.self, forKey: .dModel) ?? 1024
        activationFunction = try c.decodeIfPresent(String.self, forKey: .activationFunction) ?? "gelu"
        scaleEmbedding = try c.decodeIfPresent(Bool.self, forKey: .scaleEmbedding) ?? false
        maxSourcePositions = try c.decodeIfPresent(Int.self, forKey: .maxSourcePositions) ?? 1500
        nWindow = try c.decodeIfPresent(Int.self, forKey: .nWindow) ?? 50
        outputDim = try c.decodeIfPresent(Int.self, forKey: .outputDim) ?? 2048
        nWindowInfer = try c.decodeIfPresent(Int.self, forKey: .nWindowInfer) ?? 800
        convChunksize = try c.decodeIfPresent(Int.self, forKey: .convChunksize) ?? 500
        downsampleHiddenSize = try c.decodeIfPresent(Int.self, forKey: .downsampleHiddenSize) ?? 480
    }

    /// Mel frames per conv chunk (`n_window * 2` = 100 = 1 s at hop 160).
    public var convChunkFrames: Int { nWindow * 2 }
    /// Conv chunks per attention block (`n_window_infer / convChunkFrames` = 8 → an 8 s block).
    public var chunksPerBlock: Int { max(1, nWindowInfer / convChunkFrames) }
    /// Mel frames per attention block (800 = 8 s).
    public var blockFrames: Int { chunksPerBlock * convChunkFrames }
}

/// `thinker_config.text_config` — a standard Qwen3 decoder. The `rope_scaling` mrope block in the
/// checkpoint is a no-op for ASR (three identical position streams collapse to plain 1-D RoPE),
/// so it is deliberately not modelled.
public struct Qwen3ASRTextConfig: Codable, Sendable {
    public var vocabSize: Int = 151936
    public var hiddenSize: Int = 2048
    public var intermediateSize: Int = 6144
    public var numHiddenLayers: Int = 28
    public var numAttentionHeads: Int = 16
    public var numKeyValueHeads: Int = 8
    public var headDim: Int = 128
    public var rmsNormEps: Float = 1e-6
    public var tieWordEmbeddings: Bool = true
    public var ropeTheta: Float = 1_000_000

    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case rmsNormEps = "rms_norm_eps"
        case tieWordEmbeddings = "tie_word_embeddings"
        case ropeTheta = "rope_theta"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vocabSize = try c.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 151936
        hiddenSize = try c.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 2048
        intermediateSize = try c.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 6144
        numHiddenLayers = try c.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 28
        numAttentionHeads = try c.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 16
        numKeyValueHeads = try c.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? 8
        headDim = try c.decodeIfPresent(Int.self, forKey: .headDim) ?? 128
        rmsNormEps = try c.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1e-6
        tieWordEmbeddings = try c.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? true
        ropeTheta = try c.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 1_000_000
    }
}

/// Top-level `config.json`. Accepts both the HF layout (everything under `thinker_config`) and
/// the flattened layout some converters emit. `quantization` (mlx-community style, top-level
/// `{group_size, bits}` plus optional per-layer overrides) rides on MLXLMCommon's BaseConfiguration.
public struct Qwen3ASRConfig: Codable, Sendable {
    public var modelType: String = "qwen3_asr"
    public var audioConfig = Qwen3ASRAudioConfig()
    public var textConfig = Qwen3ASRTextConfig()
    public var audioTokenId: Int = 151676
    public var audioStartTokenId: Int = 151669
    public var audioEndTokenId: Int = 151670
    public var supportLanguages: [String] = []
    public var perLayerQuantization: BaseConfiguration.PerLayerQuantization?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case audioConfig = "audio_config"
        case textConfig = "text_config"
        case audioTokenId = "audio_token_id"
        case audioStartTokenId = "audio_start_token_id"
        case audioEndTokenId = "audio_end_token_id"
        case supportLanguages = "support_languages"
        case thinkerConfig = "thinker_config"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try c.decodeIfPresent(String.self, forKey: .modelType) ?? "qwen3_asr"
        supportLanguages = try c.decodeIfPresent([String].self, forKey: .supportLanguages) ?? []
        let inner: KeyedDecodingContainer<CodingKeys>
        if let thinker = try? c.nestedContainer(keyedBy: CodingKeys.self, forKey: .thinkerConfig) {
            inner = thinker
        } else {
            inner = c
        }
        audioConfig = try inner.decodeIfPresent(Qwen3ASRAudioConfig.self, forKey: .audioConfig) ?? Qwen3ASRAudioConfig()
        textConfig = try inner.decodeIfPresent(Qwen3ASRTextConfig.self, forKey: .textConfig) ?? Qwen3ASRTextConfig()
        audioTokenId = try inner.decodeIfPresent(Int.self, forKey: .audioTokenId) ?? 151676
        audioStartTokenId = try inner.decodeIfPresent(Int.self, forKey: .audioStartTokenId) ?? 151669
        audioEndTokenId = try inner.decodeIfPresent(Int.self, forKey: .audioEndTokenId) ?? 151670
        perLayerQuantization = (try? BaseConfiguration(from: decoder))?.perLayerQuantization
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelType, forKey: .modelType)
        try c.encode(audioConfig, forKey: .audioConfig)
        try c.encode(textConfig, forKey: .textConfig)
        try c.encode(audioTokenId, forKey: .audioTokenId)
        try c.encode(audioStartTokenId, forKey: .audioStartTokenId)
        try c.encode(audioEndTokenId, forKey: .audioEndTokenId)
        try c.encode(supportLanguages, forKey: .supportLanguages)
    }
}

/// The token ids the streaming protocol and the prompt depend on (verified at G0 against the
/// checkpoint's `added_tokens.json`).
public enum Qwen3ASRSpecialIDs {
    public static let imStart = 151644
    public static let imEnd = 151645
    public static let endOfText = 151643
    public static let audioStart = 151669
    public static let audioEnd = 151670
    public static let audioPad = 151676
    public static let asrText = 151704
    /// Greedy generation stops on either; `generation_config.json` lists both.
    public static let eos: Set<Int> = [151645, 151643]
}
