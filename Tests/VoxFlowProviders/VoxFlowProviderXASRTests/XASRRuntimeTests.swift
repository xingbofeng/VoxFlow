import Foundation
import XCTest
@testable import VoxFlowProviderXASR

private func currentResidentKiB() throws -> Int {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let value = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw NSError(domain: "xasr-rss-diagnostic", code: 1)
    }
    return value
}

final class XASRRuntimeTests: XCTestCase {
    func testAdjacentSessionsReuseRecognizerWithIndependentStreams() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        let first = try await runtime.makeStream(directoryURL: directory)
        let firstText = try await first.accept(samples: [0.25], sampleRate: 16_000)
        XCTAssertEqual(firstText, "stream-1")
        _ = try await first.finish()
        await runtime.releaseIdleResources()
        let second = try await runtime.makeStream(directoryURL: directory)
        let secondText = try await second.accept(samples: [0], sampleRate: 16_000)
        XCTAssertEqual(secondText, "stream-2")
        XCTAssertEqual(native.snapshot.loads, 1)
        XCTAssertEqual(native.snapshot.streamDestroys, 1)
        XCTAssertEqual(native.snapshot.recognizerDestroys, 0)
        await second.cancel()
        await runtime.invalidate()
    }

    func testSecondActiveStreamIsBusy() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        let first = try await runtime.makeStream(directoryURL: directory)
        await assertError(.busy) { _ = try await runtime.makeStream(directoryURL: directory) }
        XCTAssertEqual(native.snapshot.loads, 1)
        await first.cancel()
        await runtime.invalidate()
    }

    func testSilenceIsAcceptedEmptyFramesAreNotSentToNative() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let stream = try await runtime.makeStream(directoryURL: modelFixture())
        _ = try await stream.accept(samples: [], sampleRate: 16_000)
        _ = try await stream.accept(samples: [0, 0, 0], sampleRate: 16_000)
        XCTAssertEqual(native.snapshot.audio, [[0, 0, 0]])
        XCTAssertFalse(native.snapshot.calledOnMainThread)
        await stream.cancel()
        await runtime.invalidate()
    }

    func testInvalidAudioIsRejectedBeforeNativeCall() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let stream = try await runtime.makeStream(directoryURL: modelFixture())
        await assertError(.invalidAudio) { _ = try await stream.accept(samples: [0], sampleRate: 8_000) }
        for value: Float in [.nan, .infinity, -.infinity, 1.1] {
            await assertError(.invalidAudio) { _ = try await stream.accept(samples: [value], sampleRate: 16_000) }
        }
        XCTAssertTrue(native.snapshot.audio.isEmpty)
        await stream.cancel()
        await runtime.invalidate()
    }

    func testFinishPadsOneSecondAndClosesOnlyItsStream() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let stream = try await runtime.makeStream(directoryURL: modelFixture())
        let final = try await stream.finish()
        XCTAssertEqual(final, "final-1")
        XCTAssertEqual(native.snapshot.padding, [16_000])
        await assertError(.streamClosed) { _ = try await stream.finish() }
        await assertError(.streamClosed) { _ = try await stream.accept(samples: [0], sampleRate: 16_000) }
        await stream.cancel()
        XCTAssertEqual(native.snapshot.streamDestroys, 1)
        XCTAssertEqual(native.snapshot.recognizerDestroys, 0)
        await runtime.invalidate()
    }

    func testMissingFilesDoNotCallNativeFactory() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await assertError(.modelFilesMissing) { _ = try await runtime.makeStream(directoryURL: directory) }
        XCTAssertEqual(native.snapshot.loads, 0)
    }

    func testNativeAssetValidationRejectsDamagedLayoutBeforeOrtCreation() throws {
        let directory = try modelFixture()
        XCTAssertThrowsError(try XASRRuntime.validateNativeAssets(at: directory)) { error in
            XCTAssertEqual(error as? XASRRuntimeError, .modelCorrupt)
        }
    }

    func testNilRecognizerDoesNotPoisonRetry() async throws {
        let native = CapturingNativeFactory()
        native.update { $0.failRecognizer = true }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        await assertError(.recognizerCreationFailed) { _ = try await runtime.makeStream(directoryURL: directory) }
        native.update { $0.failRecognizer = false }
        let stream = try await runtime.makeStream(directoryURL: directory)
        await stream.cancel()
        XCTAssertEqual(native.snapshot.loads, 2)
        await runtime.invalidate()
    }

    func testNilStreamRetainsReusableRecognizer() async throws {
        let native = CapturingNativeFactory()
        native.update { $0.failStream = true }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        await assertError(.streamCreationFailed) { _ = try await runtime.makeStream(directoryURL: directory) }
        native.update { $0.failStream = false }
        let stream = try await runtime.makeStream(directoryURL: directory)
        XCTAssertEqual(native.snapshot.loads, 1)
        await stream.cancel()
        await runtime.invalidate()
    }

    func testIdleCacheUnloadsAtFiveMinutesWithInjectedClock() async throws {
        let native = CapturingNativeFactory()
        let clock = CapturingClock()
        addTeardownBlock { clock.wakeAll() }
        let runtime = XASRRuntime(nativeFactory: native.make, clock: clock.clock)
        let stream = try await runtime.makeStream(directoryURL: modelFixture())
        _ = try await stream.finish()
        await runtime.releaseIdleResources()
        await eventually { clock.pendingCount == 1 }
        clock.advance(by: 299)
        await eventually { clock.pendingCount == 1 }
        XCTAssertEqual(native.snapshot.recognizerDestroys, 0)
        clock.advance(by: 1)
        await eventually { native.snapshot.recognizerDestroys == 1 }
        await runtime.invalidate()
    }

    func testRestartMakesOldIdleWakeHarmless() async throws {
        let native = CapturingNativeFactory()
        let clock = CapturingClock()
        addTeardownBlock { clock.wakeAll() }
        let runtime = XASRRuntime(nativeFactory: native.make, clock: clock.clock)
        let directory = try modelFixture()
        let first = try await runtime.makeStream(directoryURL: directory)
        await first.cancel()
        await eventually { clock.pendingCount == 1 }
        let second = try await runtime.makeStream(directoryURL: directory)
        clock.advance(by: 300)
        await runtime.releaseIdleResources()
        let text = try await second.accept(samples: [0], sampleRate: 16_000)
        XCTAssertEqual(text, "stream-2")
        XCTAssertEqual(native.snapshot.loads, 1)
        XCTAssertEqual(native.snapshot.recognizerDestroys, 0)
        await second.cancel()
        await runtime.invalidate()
    }

    func testRepairInvalidatesOldStreamAndReloadsSameDirectory() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        let first = try await runtime.makeStream(directoryURL: directory)
        await runtime.invalidate()
        await assertError(.invalidated) { _ = try await first.accept(samples: [0], sampleRate: 16_000) }
        let second = try await runtime.makeStream(directoryURL: directory)
        await first.cancel()
        let text = try await second.accept(samples: [0], sampleRate: 16_000)
        XCTAssertEqual(text, "stream-2")
        XCTAssertEqual(native.snapshot.loads, 2)
        XCTAssertEqual(native.snapshot.events.prefix(4), ["load", "stream-1", "destroy-stream-1", "destroy-recognizer"])
        await second.cancel()
        await runtime.invalidate()
    }

    func testInvalidationDiscardsAnInFlightResultBeforeNativeCleanup() async throws {
        let native = CapturingNativeFactory()
        let gate = NativeGate()
        native.update { $0.beforeAccept = gate.block }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        let stream = try await runtime.makeStream(directoryURL: directory)
        let inference = Task { try await stream.accept(samples: [0], sampleRate: 16_000) }
        await fulfillment(of: [gate.entered], timeout: 2)
        runtime.requestInvalidation()
        XCTAssertEqual(native.snapshot.streamDestroys, 0)
        let cleanup = Task { await runtime.invalidate() }
        gate.resume()
        await assertError(.invalidated) { _ = try await inference.value }
        await cleanup.value
        XCTAssertEqual(native.snapshot.streamDestroys, 1)
        XCTAssertEqual(native.snapshot.recognizerDestroys, 1)
    }

    func testRevisionDirectoryChangeDestroysIdleRecognizerBeforeReload() async throws {
        let native = CapturingNativeFactory()
        let runtime = XASRRuntime(nativeFactory: native.make)
        let first = try await runtime.makeStream(directoryURL: modelFixture())
        await first.cancel()
        let second = try await runtime.makeStream(directoryURL: modelFixture())
        XCTAssertEqual(native.snapshot.loads, 2)
        XCTAssertEqual(native.snapshot.recognizerDestroys, 1)
        await second.cancel()
        await runtime.invalidate()
    }

    func testCancelledInFlightAcceptDiscardsLateTextAndAllowsNewStream() async throws {
        let native = CapturingNativeFactory()
        let gate = NativeGate()
        native.update { $0.beforeAccept = gate.block }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        let first = try await runtime.makeStream(directoryURL: directory)
        let inference = Task { try await first.accept(samples: [0], sampleRate: 16_000) }
        await fulfillment(of: [gate.entered], timeout: 2)
        inference.cancel()
        XCTAssertEqual(native.snapshot.streamDestroys, 0)
        gate.resume()
        await assertError(.streamClosed) { _ = try await inference.value }
        await first.cancel()
        native.update { $0.beforeAccept = nil }
        let second = try await runtime.makeStream(directoryURL: directory)
        await first.cancel()
        let text = try await second.accept(samples: [0], sampleRate: 16_000)
        XCTAssertEqual(text, "stream-2")
        XCTAssertEqual(native.snapshot.streamDestroys, 1)
        await second.cancel()
        await runtime.invalidate()
    }

    func testCancelledInFlightFinishDiscardsFinalWithoutDoubleDestroy() async throws {
        let native = CapturingNativeFactory()
        let gate = NativeGate()
        native.update { $0.beforeFinish = gate.block }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let stream = try await runtime.makeStream(directoryURL: modelFixture())
        let finishing = Task { try await stream.finish() }
        await fulfillment(of: [gate.entered], timeout: 2)
        finishing.cancel()
        XCTAssertEqual(native.snapshot.streamDestroys, 0)
        gate.resume()
        await assertError(.streamClosed) { _ = try await finishing.value }
        await stream.cancel()
        XCTAssertEqual(native.snapshot.streamDestroys, 1)
        await runtime.invalidate()
    }

    func testNativeFailureClosesStreamButKeepsCacheUsable() async throws {
        let native = CapturingNativeFactory()
        native.update { $0.failAccept = true }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let directory = try modelFixture()
        let first = try await runtime.makeStream(directoryURL: directory)
        await assertError(.invalidAudio) { _ = try await first.accept(samples: [0], sampleRate: 16_000) }
        native.update { $0.failAccept = false }
        let second = try await runtime.makeStream(directoryURL: directory)
        await assertError(.streamClosed) { _ = try await first.finish() }
        XCTAssertEqual(native.snapshot.loads, 1)
        await second.cancel()
        await runtime.invalidate()
    }

    func testEmptyNativeResultsRemainEmpty() async throws {
        let native = CapturingNativeFactory()
        native.update { $0.emptyResult = true }
        let runtime = XASRRuntime(nativeFactory: native.make)
        let stream = try await runtime.makeStream(directoryURL: modelFixture())
        let partial = try await stream.accept(samples: [0], sampleRate: 16_000)
        let final = try await stream.finish()
        XCTAssertEqual(partial, "")
        XCTAssertEqual(final, "")
        await runtime.invalidate()
    }

    func testRealNativeRuntimeMatchesM0AndIsolatesRepeatedStreams() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_MODEL_DIR"],
              let pcmPath = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_PCM"] else {
            throw XCTSkip("Set VOICEINPUT_TEST_XASR_MODEL_DIR and VOICEINPUT_TEST_XASR_PCM for native inference")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: pcmPath))
        XCTAssertEqual(data.count % MemoryLayout<Float>.size, 0)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let runtime = XASRRuntime()
        let directory = URL(fileURLWithPath: path)
        let first = try await runtime.makeStream(directoryURL: directory)
        var text = ""
        for offset in stride(from: 0, to: samples.count, by: 1_600) {
            text = try await first.accept(samples: Array(samples[offset..<min(offset + 1_600, samples.count)]), sampleRate: 16_000)
        }
        XCTAssertFalse(text.isEmpty)
        let final = try await first.finish()
        XCTAssertEqual(final, " 昨天是 monday ， today is 礼拜二 ， the day after tomorrow 是星期三")
        await runtime.releaseIdleResources()
        let second = try await runtime.makeStream(directoryURL: directory)
        let empty = try await second.finish()
        XCTAssertEqual(empty, "")
        let third = try await runtime.makeStream(directoryURL: directory)
        await third.cancel()
        await runtime.invalidate()
    }

    func testRealFiveMinuteIdleUnloadsAndReloadsRecognizer() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_IDLE_SMOKE"] == "1",
              let path = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_MODEL_DIR"] else {
            throw XCTSkip("Set native model path and VOICEINPUT_TEST_XASR_IDLE_SMOKE=1 for real five-minute lifecycle")
        }
        let runtime = XASRRuntime()
        let directory = URL(fileURLWithPath: path)
        let coldStart = ContinuousClock.now
        let first = try await runtime.makeStream(directoryURL: directory)
        let cold = coldStart.duration(to: .now)
        await first.cancel()
        let warmStart = ContinuousClock.now
        let second = try await runtime.makeStream(directoryURL: directory)
        let warm = warmStart.duration(to: .now)
        await second.cancel()
        await runtime.releaseIdleResources()
        print("XASR_IDLE cold=\(cold) warm=\(warm) rss_kib=\(try currentResidentKiB())")
        for tick in 1...11 {
            try await Task.sleep(for: .seconds(30))
            print("XASR_IDLE elapsed=\(tick * 30)s rss_kib=\(try currentResidentKiB())")
        }
        let reloadStart = ContinuousClock.now
        let third = try await runtime.makeStream(directoryURL: directory)
        let reload = reloadStart.duration(to: .now)
        XCTAssertLessThan(warm, .milliseconds(100))
        XCTAssertGreaterThan(reload, warm)
        print("XASR_IDLE reload=\(reload) rss_kib=\(try currentResidentKiB())")
        await third.cancel()
        await runtime.invalidate()
        print("XASR_IDLE invalidated_rss_kib=\(try currentResidentKiB())")
    }

    private func eventually(
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Condition did not become true", file: file, line: line)
    }

    private func modelFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xasr-runtime-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["encoder-480ms.onnx", "decoder-480ms.onnx", "joiner-480ms.onnx", "tokens.txt"] {
            try Data([1]).write(to: directory.appendingPathComponent(name))
        }
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func assertError(
        _ expected: XASRRuntimeError,
        file: StaticString = #filePath, line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? XASRRuntimeError, expected, file: file, line: line)
        }
    }
}

private final class CapturingNativeFactory: @unchecked Sendable {
    struct State {
        var loads = 0
        var streams = 0
        var streamDestroys = 0
        var recognizerDestroys = 0
        var audio: [[Float]] = []
        var padding: [Int] = []
        var failRecognizer = false
        var failStream = false
        var failAccept = false
        var emptyResult = false
        var beforeAccept: (@Sendable () -> Void)?
        var beforeFinish: (@Sendable () -> Void)?
        var events: [String] = []
        var calledOnMainThread = false
    }
    private let lock = NSLock()
    private var state = State()
    var snapshot: State { lock.withLock { state } }
    @discardableResult
    func update<T>(_ body: (inout State) -> T) -> T { lock.withLock { body(&state) } }
    func make(_ directory: URL) -> (any XASRNativeRecognizer)? {
        let failed = update {
            $0.loads += 1
            $0.events.append("load")
            $0.calledOnMainThread = $0.calledOnMainThread || Thread.isMainThread
            return $0.failRecognizer
        }
        return failed ? nil : CapturingRecognizer(owner: self)
    }
}

private final class CapturingRecognizer: XASRNativeRecognizer {
    let owner: CapturingNativeFactory
    init(owner: CapturingNativeFactory) { self.owner = owner }
    func makeStream() -> (any XASRNativeStream)? {
        let id = owner.update { state -> Int? in
            guard !state.failStream else { return nil }
            state.streams += 1
            state.events.append("stream-\(state.streams)")
            return state.streams
        }
        return id.map { CapturingStream(owner: owner, id: $0) }
    }
    func destroy() {
        owner.update { $0.recognizerDestroys += 1; $0.events.append("destroy-recognizer") }
    }
}

private final class CapturingStream: XASRNativeStream {
    let owner: CapturingNativeFactory
    let id: Int
    init(owner: CapturingNativeFactory, id: Int) { self.owner = owner; self.id = id }
    func accept(samples: [Float]) throws -> String {
        owner.snapshot.beforeAccept?()
        if owner.snapshot.failAccept { throw XASRRuntimeError.invalidAudio }
        owner.update {
            $0.audio.append(samples)
            $0.calledOnMainThread = $0.calledOnMainThread || Thread.isMainThread
        }
        return owner.snapshot.emptyResult ? "" : "stream-\(id)"
    }
    func finish(tailPaddingSamples: Int) throws -> String {
        owner.snapshot.beforeFinish?()
        owner.update { $0.padding.append(tailPaddingSamples) }
        return owner.snapshot.emptyResult ? "" : "final-\(id)"
    }
    func destroy() {
        owner.update { $0.streamDestroys += 1; $0.events.append("destroy-stream-\(id)") }
    }
}

private final class NativeGate: @unchecked Sendable {
    let entered = XCTestExpectation(description: "native call entered")
    private let semaphore = DispatchSemaphore(value: 0)
    func block() {
        entered.fulfill()
        XCTAssertEqual(semaphore.wait(timeout: .now() + 5), .success)
    }
    func resume() { semaphore.signal() }
}

private final class CapturingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    var pendingCount: Int { lock.withLock { sleepers.count } }
    var clock: XASRRuntimeClock {
        XASRRuntimeClock(now: { self.lock.withLock { self.time } }, sleep: { _ in
            await withCheckedContinuation { continuation in
                self.lock.withLock { self.sleepers.append(continuation) }
            }
        })
    }
    func advance(by seconds: TimeInterval) {
        let pending = lock.withLock {
            time += seconds
            let pending = sleepers
            sleepers = []
            return pending
        }
        pending.forEach { $0.resume() }
    }
    func wakeAll() { advance(by: 0) }
}
