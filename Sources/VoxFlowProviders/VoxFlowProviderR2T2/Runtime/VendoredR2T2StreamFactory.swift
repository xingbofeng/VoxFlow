@preconcurrency import VoxFlowR2T2Core
import Foundation

/// 串行化落在同一份已加载模型上的推理。
///
/// 上游 `Qwen3ASRModel` 持有 MLX 权重，`R2T2Stream` 在其上跑 encoder + `generate`。同目录的
/// 多个 stream 共享同一个 model 实例，只有 KV cache 是各自独立的（`model.model.newCache()`）。
/// 两次推理交叠会让 MLX 的 GPU 提交互相穿插，也会让模型的惰性求值跨线程共享中间数组。
///
/// 因此模型缓存为每个已加载模型配一把 gate，每次 `push` / `finish` 都从这里过。
/// gate 只包住一次推理，不独占整个会话，所以多路会话仍然可以交替推进。
final class R2T2InferenceGate: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.voxflow.r2t2.inference")

    func run<T>(_ body: () -> T) -> T {
        queue.sync(execute: body)
    }
}

/// 用隔离 runtime（`Packages/VoxFlowR2T2Core`）实现的 R2T2 engine。
///
/// 上游 `R2T2Stream` 是可变类且非线程安全。driver 是一个 actor，串行化本对象的全部调用；
/// 跨会话的共享模型由 `R2T2InferenceGate` 串行化。因此这里以 `@unchecked Sendable` 声明；
/// 不要在本类型之外并发访问同一个实例。
final class VendoredR2T2Stream: R2T2StreamingEngine, @unchecked Sendable {
    private let stream: R2T2Stream
    private let gate: R2T2InferenceGate

    init(stream: R2T2Stream, gate: R2T2InferenceGate) {
        self.stream = stream
        self.gate = gate
    }

    func push(_ samples: [Float]) -> [String] {
        gate.run { stream.push(samples) }
    }

    func finish() -> String {
        gate.run { stream.finish() }
    }

    var committedText: String { stream.committedText }

    var pendingText: String { stream.pendingText }

    var detectedLanguage: String { stream.language }

    /// 上游没有取消 API：释放本次 stream（连同其 KV cache）即是取消。
    /// 模型权重留在缓存中供下次会话复用。
    func cancel() {}
}

/// 生产环境的 R2T2 engine 工厂。模型按目录缓存，避免每次按住快捷键都重新加载约 2.46 GB 权重。
public struct VendoredR2T2StreamFactory: R2T2StreamMaking {
    private let modelCache: VendoredR2T2ModelCache

    public init() {
        self.modelCache = .shared
    }

    init(modelCache: VendoredR2T2ModelCache) {
        self.modelCache = modelCache
    }

    public func makeStream(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any R2T2StreamingEngine {
        try await modelCache.makeStream(
            modelURL: modelURL,
            languageHint: languageHint,
            contextPrompt: contextPrompt
        )
    }

    /// 释放已加载的模型权重，供闲置资源回收调用。
    public static func releaseSharedModels() async {
        await VendoredR2T2ModelCache.shared.removeAll()
    }
}

/// 已加载 R2T2 模型的缓存。
///
/// 上游 `Qwen3ASRModel` 与 `R2T2Stream` 都不是 Sendable；本 actor 是它们的唯一所有者，
/// stream 在 actor 内构造后以 `@unchecked Sendable` 包装交给调用方的 driver actor 串行使用。
actor VendoredR2T2ModelCache {
    static let shared = VendoredR2T2ModelCache()

    private struct CachedModel {
        let model: Qwen3ASRModel
        let gate: R2T2InferenceGate
    }
    private struct ModelLoad {
        let token: Int
        let task: Task<Qwen3ASRModel, Error>
    }

    private var models: [URL: CachedModel] = [:]
    private var loads: [URL: ModelLoad] = [:]
    private var nextLoadToken = 0
    /// 每次 `removeAll()` 递增。加载完成后只有 generation 未变才写回缓存。
    private var generation = 0

    func makeStream(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any R2T2StreamingEngine {
        let cached = try await cachedModel(at: modelURL)
        let stream = R2T2Stream(
            model: cached.model,
            language: languageHint,
            context: contextPrompt ?? ""
        )
        return VendoredR2T2Stream(stream: stream, gate: cached.gate)
    }

    private func cachedModel(at modelURL: URL) async throws -> CachedModel {
        let key = modelURL.standardizedFileURL
        if let cached = models[key] {
            return cached
        }

        let token: Int
        let generationAtStart = generation
        let task: Task<Qwen3ASRModel, Error>
        if let load = loads[key] {
            (token, task) = (load.token, load.task)
        } else {
            nextLoadToken += 1
            token = nextLoadToken
            task = Task {
                let model = try Qwen3ASRModel.load(directory: key)
                try await model.loadTokenizer(directory: key)
                return model
            }
            loads[key] = ModelLoad(token: token, task: task)
        }

        do {
            let model = try await task.value
            clearLoad(for: key, token: token)
            // 同一个 key 的并发加载会汇合到同一把 gate 上；后到的调用复用先到的结果。
            if let cached = models[key] {
                return cached
            }
            let cached = CachedModel(model: model, gate: R2T2InferenceGate())
            // `removeAll()` 可能在加载期间清空了缓存。此时不写回，避免刚被释放的约 2.46 GB
            // 权重立刻复活；结果仍交给本次调用方使用。
            if generation == generationAtStart {
                models[key] = cached
            }
            return cached
        } catch {
            clearLoad(for: key, token: token)
            throw error
        }
    }

    private func clearLoad(for key: URL, token: Int) {
        guard loads[key]?.token == token else { return }
        loads[key] = nil
    }

    func removeAll() {
        generation += 1
        for load in loads.values {
            load.task.cancel()
        }
        loads.removeAll(keepingCapacity: false)
        models.removeAll(keepingCapacity: false)
    }
}
