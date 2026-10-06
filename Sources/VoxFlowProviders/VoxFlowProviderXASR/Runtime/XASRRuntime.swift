import CSherpaOnnx
import Darwin
import Foundation
import VoxFlowModelStore

public enum XASRRuntimeError: Error, Sendable, Equatable {
    case modelFilesMissing
    case modelCorrupt
    case recognizerCreationFailed
    case streamCreationFailed
    case busy
    case invalidAudio
    case streamClosed
    case invalidated
}

public protocol XASRStreaming: Sendable {
    func accept(samples: [Float], sampleRate: Int) async throws -> String
    func finish() async throws -> String
    func cancel() async
}

public protocol XASRStreamMaking: Sendable {
    func makeStream(directoryURL: URL) async throws -> any XASRStreaming
}

// Only the synchronous native boundary is substituted by weight-free tests.
internal protocol XASRNativeRecognizer: AnyObject {
    func makeStream() -> (any XASRNativeStream)?
    func destroy()
}

internal protocol XASRNativeStream: AnyObject {
    func accept(samples: [Float]) throws -> String
    func finish(tailPaddingSamples: Int) throws -> String
    func destroy()
}

internal struct XASRRuntimeClock: Sendable {
    var now: @Sendable () -> TimeInterval
    var sleep: @Sendable (TimeInterval) async throws -> Void

    static let continuous = Self(
        now: { ProcessInfo.processInfo.systemUptime },
        sleep: { try await Task.sleep(for: .seconds($0)) }
    )
}

public final class XASRRuntime: XASRStreamMaking, @unchecked Sendable {
    // Native objects and cache state are accessed exclusively on this queue.
    private let queue = DispatchQueue(label: "com.voxflow.xasr.inference", qos: .userInitiated)
    private let nativeFactory: @Sendable (URL) throws -> (any XASRNativeRecognizer)?
    private let clock: XASRRuntimeClock
    private var recognizer: (any XASRNativeRecognizer)?
    private var directory: URL?
    private var active: XASRStreamState?
    private var idleTask: Task<Void, Never>?
    private var idleSince: TimeInterval?
    private var idleGeneration: UInt64 = 0
    // This lock publishes only lease invalidation; native pointers remain queue-owned.
    private let invalidationLock = NSLock()
    private var invalidationGeneration: UInt64 = 0
    private var invalidatableStream: XASRStreamState?

    public convenience init() { self.init(nativeFactory: { try XASROnlineRecognizer(directory: $0) }) }

    internal init(
        nativeFactory: @escaping @Sendable (URL) throws -> (any XASRNativeRecognizer)?,
        clock: XASRRuntimeClock = .continuous
    ) {
        self.nativeFactory = nativeFactory
        self.clock = clock
    }

    deinit {
        idleTask?.cancel()
        active?.native.destroy()
        recognizer?.destroy()
    }

    public func makeStream(directoryURL: URL) async throws -> any XASRStreaming {
        let generation = invalidationLock.withLock { invalidationGeneration }
        return try await perform {
            guard self.active == nil else { throw XASRRuntimeError.busy }
            let directory = directoryURL.standardizedFileURL
            guard XASRModel.modelsExist(at: directory) else { throw XASRRuntimeError.modelFilesMissing }
            self.cancelIdleRelease()
            if self.directory != directory {
                self.recognizer?.destroy()
                self.recognizer = nil
                self.directory = nil
            }
            if self.recognizer == nil {
                guard let recognizer = try self.nativeFactory(directory) else {
                    throw XASRRuntimeError.recognizerCreationFailed
                }
                self.recognizer = recognizer
                self.directory = directory
            }
            guard let native = self.recognizer?.makeStream() else {
                self.scheduleIdleRelease()
                throw XASRRuntimeError.streamCreationFailed
            }
            let state = XASRStreamState(native: native)
            let valid = self.invalidationLock.withLock {
                guard self.invalidationGeneration == generation else { return false }
                self.invalidatableStream = state
                return true
            }
            guard valid else {
                native.destroy()
                throw XASRRuntimeError.invalidated
            }
            self.active = state
            return XASRStream(runtime: self, state: state)
        }
    }

    /// Normal stop keeps the recognizer warm; repeated calls do not extend its deadline.
    public func releaseIdleResources() async {
        await perform { self.scheduleIdleRelease() }
    }
    public func invalidate() async {
        requestInvalidation()
        await perform {
            self.cancelIdleRelease()
            if let active = self.active {
                active.close(.invalidated)
                self.release(active)
            }
            self.recognizer?.destroy()
            self.recognizer = nil
            self.directory = nil
        }
    }

    internal func requestInvalidation() {
        let stream = invalidationLock.withLock {
            invalidationGeneration &+= 1
            return invalidatableStream
        }
        stream?.close(.invalidated)
    }

    internal static func validateNativeAssets(at directory: URL) throws {
        guard XASRModel.modelsExist(at: directory) else { throw XASRRuntimeError.modelFilesMissing }
        let manifest = try XASRManifestCatalog.modelStoreManifest()
        let report = try ModelIntegrityValidator().validate(manifest: manifest, installedRoot: directory, runtimeVersion: XASRManifestCatalog.runtimeVersion)
        guard report.isValid else { throw XASRRuntimeError.modelCorrupt }
    }

    fileprivate func accept(_ state: XASRStreamState, samples: [Float], sampleRate: Int) async throws -> String {
        try await withTaskCancellationHandler {
            try state.checkOpen()
            return try await perform {
            try state.checkOpen()
            guard sampleRate == XASRModel.sampleRate, samples.count <= Int(Int32.max),
                  samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else {
                throw XASRRuntimeError.invalidAudio
            }
            guard !samples.isEmpty else { return "" }
            do {
                let text = try state.native.accept(samples: samples)
                try state.checkOpen()
                return text
            } catch {
                state.close(.streamClosed)
                self.release(state)
                throw error
            }
            }
        } onCancel: {
            self.requestCancel(state)
        }
    }

    fileprivate func finish(_ state: XASRStreamState) async throws -> String {
        try await withTaskCancellationHandler {
            try state.checkOpen()
            return try await perform {
            try state.checkOpen()
            defer {
                state.close(.streamClosed)
                self.release(state)
            }
            let text = try state.native.finish(tailPaddingSamples: Int(XASRModel.tailPaddingSeconds * Double(XASRModel.sampleRate)))
            try state.checkOpen()
            return text
            }
        } onCancel: {
            self.requestCancel(state)
        }
    }

    fileprivate func cancel(_ state: XASRStreamState) async {
        state.close(.streamClosed)
        await perform { self.release(state) }
    }

    private func requestCancel(_ state: XASRStreamState) {
        state.close(.streamClosed)
        queue.async { self.release(state) }
    }

    private func release(_ state: XASRStreamState) {
        guard self.active === state else { return }
        state.native.destroy()
        self.active = nil
        invalidationLock.withLock {
            if invalidatableStream === state { invalidatableStream = nil }
        }
        scheduleIdleRelease()
    }

    private func cancelIdleRelease() {
        idleGeneration &+= 1
        idleTask?.cancel()
        idleTask = nil
        idleSince = nil
    }

    private func scheduleIdleRelease() {
        guard active == nil, recognizer != nil, idleTask == nil else { return }
        let since = idleSince ?? clock.now()
        idleSince = since
        let generation = idleGeneration
        let clock = clock
        idleTask = Task { [weak self] in
            var remaining = max(0, since + 300 - clock.now())
            while !Task.isCancelled {
                do { try await clock.sleep(remaining) } catch { return }
                guard !Task.isCancelled, let runtime = self else { return }
                remaining = (try? await runtime.perform {
                    guard runtime.idleGeneration == generation, runtime.active == nil else { return 0.0 }
                    let remaining = since + 300 - clock.now()
                    guard remaining <= 0 else { return remaining }
                    runtime.recognizer?.destroy()
                    runtime.recognizer = nil
                    runtime.directory = nil
                    runtime.idleTask = nil
                    runtime.idleSince = nil
                    return 0.0
                }) ?? 0
                if remaining <= 0 { return }
            }
        }
    }

    private func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func perform(_ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                body()
                continuation.resume()
            }
        }
    }
}

/// Official 1.13.3 Online API. All entry points run on the owner's inference queue.
private final class XASROnlineRecognizer: XASRNativeRecognizer {
    private let pointer: OpaquePointer

    init(directory: URL) throws {
        try XASRRuntime.validateNativeAssets(at: directory)
        let strings = [XASRModel.encoderPath, XASRModel.decoderPath, XASRModel.joinerPath, XASRModel.tokensPath]
            .map { directory.appendingPathComponent($0).path } + ["cpu", "greedy_search", "zipformer2"]
        let pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        guard pointers.allSatisfy({ $0 != nil }) else { throw XASRRuntimeError.recognizerCreationFailed }
        // The vendored C implementation copies these strings into std::string during creation.
        var config = SherpaOnnxOnlineRecognizerConfig()
        config.feat_config.sample_rate = Int32(XASRModel.sampleRate)
        config.feat_config.feature_dim = 80
        config.model_config.transducer.encoder = UnsafePointer(pointers[0])
        config.model_config.transducer.decoder = UnsafePointer(pointers[1])
        config.model_config.transducer.joiner = UnsafePointer(pointers[2])
        config.model_config.tokens = UnsafePointer(pointers[3])
        config.model_config.provider = UnsafePointer(pointers[4])
        config.model_config.num_threads = XASRModel.numThreads
        config.model_config.model_type = UnsafePointer(pointers[6])
        config.decoding_method = UnsafePointer(pointers[5])
        config.max_active_paths = 4
        config.enable_endpoint = 0
        guard let pointer = SherpaOnnxCreateOnlineRecognizer(&config) else {
            throw XASRRuntimeError.recognizerCreationFailed
        }
        self.pointer = pointer
    }

    func makeStream() -> (any XASRNativeStream)? {
        SherpaOnnxCreateOnlineStream(pointer).map { XASROnlineStream(recognizer: pointer, stream: $0) }
    }

    func destroy() { SherpaOnnxDestroyOnlineRecognizer(pointer) }
}

private final class XASROnlineStream: XASRNativeStream {
    private let recognizer: OpaquePointer
    private let stream: OpaquePointer

    init(recognizer: OpaquePointer, stream: OpaquePointer) {
        self.recognizer = recognizer
        self.stream = stream
    }

    func accept(samples: [Float]) throws -> String {
        feed(samples)
        return drainAndCopyText()
    }

    func finish(tailPaddingSamples: Int) throws -> String {
        feed([Float](repeating: 0, count: tailPaddingSamples))
        SherpaOnnxOnlineStreamInputFinished(stream)
        return drainAndCopyText()
    }

    private func feed(_ samples: [Float]) {
        samples.withUnsafeBufferPointer {
            SherpaOnnxOnlineStreamAcceptWaveform(stream, Int32(XASRModel.sampleRate), $0.baseAddress, Int32($0.count))
        }
    }

    private func drainAndCopyText() -> String {
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { return "" }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        let copy = Data(bytes: text, count: strlen(text))
        return String(decoding: copy, as: UTF8.self)
    }

    func destroy() { SherpaOnnxDestroyOnlineStream(stream) }
}

private final class XASRStreamState: @unchecked Sendable {
    let native: any XASRNativeStream
    private let lock = NSLock()
    private var error: XASRRuntimeError?

    init(native: any XASRNativeStream) { self.native = native }
    func close(_ error: XASRRuntimeError) { lock.withLock { if self.error == nil { self.error = error } } }
    func checkOpen() throws {
        try lock.withLock { if let error { throw error } }
    }
}

private final class XASRStream: XASRStreaming {
    let runtime: XASRRuntime
    let state: XASRStreamState
    init(runtime: XASRRuntime, state: XASRStreamState) { self.runtime = runtime; self.state = state }
    func accept(samples: [Float], sampleRate: Int) async throws -> String {
        try await runtime.accept(state, samples: samples, sampleRate: sampleRate)
    }
    func finish() async throws -> String { try await runtime.finish(state) }
    func cancel() async { await runtime.cancel(state) }
}
