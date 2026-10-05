import Foundation
import MLX
import MLXLMCommon
import MLXNN
import Tokenizers

public enum Qwen3ASRError: Error, CustomStringConvertible {
    case missingFile(String)
    case noWeights(String)
    case keyContract(missing: [String], unused: [String])
    public var description: String {
        switch self {
        case .missingFile(let f): return "missing \(f)"
        case .noWeights(let d): return "no .safetensors in \(d)"
        case .keyContract(let m, let u): return "key contract: \(m.count) missing, \(u.count) unused" +
            (m.isEmpty ? "" : " — missing e.g. \(m.prefix(3))") + (u.isEmpty ? "" : " — unused e.g. \(u.prefix(3))")
        }
    }
}

public enum Qwen3ASRWeights {
    /// Every `*.safetensors` in `directory`, merged.
    public static func load(directory: URL) throws -> [String: MLXArray] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".safetensors") }.sorted()
        guard !names.isEmpty else { throw Qwen3ASRError.noWeights(directory.path) }
        var all: [String: MLXArray] = [:]
        for n in names {
            for (k, v) in try loadArrays(url: directory.appendingPathComponent(n)) { all[k] = v }
        }
        return all
    }

    /// HF checkpoint → module keys: strip `thinker.`, drop the tied `lm_head.weight`, and move
    /// PyTorch `[out, in, kh, kw]` Conv2d kernels to MLX's `[out, kh, kw, in]`. A repo the
    /// mlx-audio converter wrote is already in this layout (no `thinker.` prefix) and is left alone.
    public static func sanitize(_ weights: [String: MLXArray], tied: Bool) -> [String: MLXArray] {
        let fromHF = weights.keys.contains { $0.hasPrefix("thinker.") }
        var out: [String: MLXArray] = [:]
        for (key, value) in weights {
            var k = key
            if k.hasPrefix("thinker.") { k = String(k.dropFirst("thinker.".count)) }
            if tied && k == "lm_head.weight" { continue }
            var v = value
            if fromHF && k.contains("conv2d") && k.hasSuffix("weight") && v.ndim == 4 {
                v = v.transposed(0, 2, 3, 1)
            }
            out[k] = v
        }
        return out
    }
}

extension Qwen3ASRModel {
    /// Loads a repo directory: `config.json`, `tokenizer.json` (+ its config), and the shards.
    /// A quantised repo (top-level `quantization` in config.json, mlx-community style) rebuilds
    /// the quantised modules BEFORE the weights land — exactly the modules that carry `.scales`
    /// in the file, which is the LM (Linear + the embedding table); the audio tower stays bf16.
    /// `dtype` casts every non-quantised parameter (fp32 on the CPU stream is the parity setting).
    public static func load(directory: URL, dtype: DType? = nil) throws -> Qwen3ASRModel {
        let configURL = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else { throw Qwen3ASRError.missingFile("config.json") }
        let config = try JSONDecoder().decode(Qwen3ASRConfig.self, from: Data(contentsOf: configURL))
        let model = Qwen3ASRModel(config)
        let raw = try Qwen3ASRWeights.load(directory: directory)
        let weights = Qwen3ASRWeights.sanitize(raw, tied: config.textConfig.tieWordEmbeddings)
        if let q = config.perLayerQuantization {
            quantize(model: model) { path, module in
                guard !path.hasPrefix("audio_tower"), weights["\(path).scales"] != nil else { return nil }
                return q.quantization(layer: path)?.asTuple
            }
        }
        let expected = Set(model.parameters().flattened().map { $0.0 })
        let provided = Set(weights.keys)
        let missing = expected.subtracting(provided).sorted()
        let unused = provided.subtracting(expected).sorted()
        guard missing.isEmpty, unused.isEmpty else { throw Qwen3ASRError.keyContract(missing: missing, unused: unused) }
        var params = weights
        if let dtype {
            for (k, v) in params where v.dtype != .uint32 && !k.hasSuffix(".scales") && !k.hasSuffix(".biases") {
                params[k] = v.asType(dtype)
            }
        }
        try model.update(parameters: ModuleParameters.unflattened(params), verify: .all)
        eval(model)
        return model
    }

    /// The Qwen byte-level BPE from `tokenizer.json` next to the weights.
    public func loadTokenizer(directory: URL) async throws {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("tokenizer.json").path) else {
            throw Qwen3ASRError.missingFile("tokenizer.json")
        }
        tokenizer = try await AutoTokenizer.from(modelFolder: directory)
    }
}
