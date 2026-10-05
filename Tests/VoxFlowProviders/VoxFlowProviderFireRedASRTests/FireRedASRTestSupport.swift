import Foundation
import VoxFlowASRCore
import XCTest
@testable import VoxFlowProviderFireRedASR

// MARK: - ASREvent convenience

extension ASREvent {
    var isFinal: Bool {
        guard case .final = self else { return false }
        return true
    }

    var isPartial: Bool {
        guard case .partial = self else { return false }
        return true
    }

    var partialTranscript: PartialTranscript? {
        guard case let .partial(_, transcript) = self else { return nil }
        return transcript
    }

    var isFailure: Bool {
        guard case .failure = self else { return false }
        return true
    }

    var isReady: Bool {
        guard case .ready = self else { return false }
        return true
    }

    var finalText: String? {
        guard case let .final(_, _, text) = self else { return nil }
        return text
    }

    var failureCategory: ASRErrorCategory? {
        guard case let .failure(_, _, error) = self else { return nil }
        return error.category
    }
}

// MARK: - Fakes

/// 每次调用都返回同一个结果，并记录调用次数。
actor CapturingFireRedASRTranscriber: FireRedASRTranscribing {
    let result: String
    private(set) var invocationCount = 0
    private(set) var makeCount = 0
    private(set) var lastAudioSampleCount = 0

    init(result: String) {
        self.result = result
    }

    func markMade() {
        makeCount += 1
    }

    func transcribe(audio: [Float]) async throws -> String {
        invocationCount += 1
        lastAudioSampleCount = audio.count
        return result
    }
}

/// 按调用顺序返回不同结果，用来验证「分段解码 → 保序拼接」。
actor SequencedFireRedASRTranscriber: FireRedASRTranscribing {
    private let texts: [String]
    private(set) var invocationCount = 0

    init(texts: [String]) {
        self.texts = texts
    }

    func transcribe(audio: [Float]) async throws -> String {
        let index = invocationCount
        invocationCount += 1
        guard index < texts.count else { return "" }
        return texts[index]
    }
}

/// 第一次 `transcribe` 挂住直到 `release()`，之后放行。
///
/// 用来把「预览解码正在飞」这一瞬间钉住，从而确定性地复现 `finish()` / `cancel()`
/// 与预览任务之间的竞态——否则 fake 立即返回，竞态窗口根本不会出现。
/// 注意：调用方必须用有超时的等待去观察 `invocationCount`，不要用无超时的 await，
/// 否则在「根本没有预览调度」的失败态下会永久挂住测试进程。
actor GatedFireRedASRTranscriber: FireRedASRTranscribing {
    private let result: String
    private var shouldBlockNextCall = true
    private var gateContinuation: CheckedContinuation<Void, Never>?
    private(set) var invocationCount = 0

    init(result: String) {
        self.result = result
    }

    func transcribe(audio: [Float]) async throws -> String {
        invocationCount += 1
        if shouldBlockNextCall {
            shouldBlockNextCall = false
            await withCheckedContinuation { gateContinuation = $0 }
        }
        return result
    }

    func release() {
        gateContinuation?.resume()
        gateContinuation = nil
    }
}

/// 第一次调用抛错（预览解码失败），之后正常返回。
///
/// 用来验证「一次预览失败不得毁掉整个会话」——`finish()` 仍应整段重解出 final。
actor FailFirstFireRedASRTranscriber: FireRedASRTranscribing {
    struct PreviewFailure: Error {}

    private let result: String
    private var shouldFailNextCall = true
    private(set) var invocationCount = 0

    init(result: String) {
        self.result = result
    }

    func transcribe(audio: [Float]) async throws -> String {
        invocationCount += 1
        if shouldFailNextCall {
            shouldFailNextCall = false
            throw PreviewFailure()
        }
        return result
    }
}

/// 直接返回给定 transcriber，不做任何计数。
struct StaticFireRedASRTranscriberFactory: FireRedASRTranscriberMaking {
    let transcriber: any FireRedASRTranscribing

    func makeTranscriber(directoryURL: URL) async throws -> any FireRedASRTranscribing {
        transcriber
    }
}

struct CapturingFireRedASRTranscriberFactory: FireRedASRTranscriberMaking {
    let transcriber: CapturingFireRedASRTranscriber

    func makeTranscriber(directoryURL: URL) async throws -> any FireRedASRTranscribing {
        await transcriber.markMade()
        return transcriber
    }
}

/// 卡在 `makeTranscriber` 里直到 `release()`，用来复现「加载 1.24 GB 权重期间用户取消」。
final class DelayedFireRedASRTranscriberFactory: FireRedASRTranscriberMaking, @unchecked Sendable {
    private let lock = NSLock()
    private let transcriber: any FireRedASRTranscribing
    private var started = false
    private var continuation: CheckedContinuation<any FireRedASRTranscribing, Error>?

    var hasStarted: Bool {
        lock.withLock { started }
    }

    init(transcriber: any FireRedASRTranscribing) {
        self.transcriber = transcriber
    }

    func makeTranscriber(directoryURL: URL) async throws -> any FireRedASRTranscribing {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<any FireRedASRTranscribing, Error>? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: transcriber)
    }
}

// MARK: - Recorders

actor FireRedASREventRecorder {
    private var events: [ASREvent] = []

    func append(_ event: ASREvent) {
        events.append(event)
    }

    func snapshot() -> [ASREvent] {
        events
    }
}

final class FireRedASRSegmentationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: FireRedASRSegmentationReport?

    var report: FireRedASRSegmentationReport? {
        lock.withLock { storage }
    }

    func record(_ report: FireRedASRSegmentationReport) {
        lock.withLock { storage = report }
    }
}

// MARK: - Async assertions

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure @escaping () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure @escaping () async throws -> T,
    _ validation: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        validation(error)
    }
}

func waitUntil(
    timeout: TimeInterval,
    pollInterval: UInt64 = 10_000_000,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollInterval)
    }
    return await condition()
}
