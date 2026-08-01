import XCTest
@testable import VoxFlowMobileCore
import VoxFlowASRRuntime
import VoxFlowAudio

final class MobileDictationSessionTests: XCTestCase {
    private final class FakeASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
        let lock = NSLock()
        private var started = false
        var available = true
        var onTranscription: ((String, Bool) -> Void)?
        var onError: ((Error) -> Void)?

        var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot { .init() }

        var isAvailable: Bool { lock.withLock { available } }

        func configure(locale: Locale) {}

        func start() throws {
            let avail = lock.withLock { available }
            guard avail else { throw FakeEngineError.notConfigured }
            lock.withLock { started = true }
        }

        func appendAudioFrame(_ frame: AudioFrame) {}

        func endAudio() {
            lock.withLock { started = false }
        }

        func stop() { cancel() }

        func cancel() {
            lock.withLock { started = false }
        }

        var isStarted: Bool { lock.withLock { started } }

        func emitPartial(_ text: String) {
            let cb = lock.withLock { onTranscription }
            cb?(text, false)
        }

        func emitFinal(_ text: String) {
            let cb = lock.withLock { onTranscription }
            cb?(text, true)
        }

        func emitError(_ error: Error) {
            let cb = lock.withLock { onError }
            cb?(error)
        }
    }

    private enum FakeEngineError: Error { case notConfigured }

    private final class FakeRecorder: MobileAudioRecording, @unchecked Sendable {
        let lock = NSLock()
        private var stopped = false
        var permissionGranted = true
        var permissionThrows = false
        var startThrowing = false
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func requestPermission() async throws -> Bool {
            if permissionThrows { throw FakeRecorderError.permissionFailed }
            return lock.withLock { permissionGranted }
        }

        func start(onFrame: @escaping @Sendable (AudioFrame) -> Void) throws {
            if startThrowing { throw FakeRecorderError.startFailed }
            lock.withLock {
                startCount += 1
                stopped = false
            }
        }

        func stop() {
            lock.withLock {
                stopCount += 1
                stopped = true
            }
        }

        var stopCalled: Bool { lock.withLock { stopCount > 0 } }
    }

    private enum FakeRecorderError: Error { case permissionFailed, startFailed }

    private func drainMain() {
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }

    func testStartReachesRecordingWhenPermissionAndEngineAvailable() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)
        var states: [MobileDictationState] = []
        session.onChange = { states.append($0) }

        await session.start()
        drainMain()

        XCTAssertEqual(session.currentState(), .recording(liveText: ""))
        XCTAssertTrue(engine.isStarted)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertTrue(states.contains(.requestingPermission))
        XCTAssertTrue(states.contains(.recording(liveText: "")))
    }

    func testStartFailsWhenPermissionDenied() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        recorder.permissionGranted = false
        let session = MobileDictationSession(engine: engine, recorder: recorder)
        var permissionDeniedCalled = false
        session.onPermissionDenied = { permissionDeniedCalled = true }

        await session.start()

        if case let .failed(message) = session.currentState() {
            XCTAssertEqual(message, "麦克风权限被拒绝，请在系统设置中授权。")
        } else {
            XCTFail("expected failed state, got \(session.currentState())")
        }
        XCTAssertTrue(permissionDeniedCalled)
        XCTAssertFalse(engine.isStarted)
    }

    func testStartFailsWhenEngineNotAvailable() async {
        let engine = FakeASREngine()
        engine.available = false
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()

        if case let .failed(message) = session.currentState() {
            XCTAssertEqual(message, "所选 ASR Provider 未配置凭证。")
        } else {
            XCTFail("expected failed state, got \(session.currentState())")
        }
        XCTAssertFalse(engine.isStarted)
    }

    func testStartFailsWhenRecorderStartThrows() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        recorder.startThrowing = true
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()

        if case .failed = session.currentState() {
        } else {
            XCTFail("expected failed state, got \(session.currentState())")
        }
    }

    func testPartialTransitionsToRecordingWithLiveText() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        engine.emitPartial("你好")
        drainMain()

        XCTAssertEqual(session.currentState(), .recording(liveText: "你好"))
    }

    func testFinalTransitionsToFinished() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        engine.emitFinal("你好世界")
        drainMain()

        XCTAssertEqual(session.currentState(), .finished(text: "你好世界"))
    }

    func testErrorTransitionsToFailed() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        engine.emitError(FakeEngineError.notConfigured)
        drainMain()

        if case .failed = session.currentState() {
        } else {
            XCTFail("expected failed, got \(session.currentState())")
        }
    }

    func testStopTransitionsToTranscribingAndKeepsLiveText() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        engine.emitPartial("正在说")
        drainMain()
        session.stop()

        XCTAssertEqual(session.currentState(), .transcribing(liveText: "正在说"))
        XCTAssertTrue(recorder.stopCalled)
    }

    func testStopThenFinalTransitionsToFinished() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        engine.emitPartial("正在说")
        drainMain()
        session.stop()
        engine.emitPartial("正在说更多")
        drainMain()

        XCTAssertEqual(session.currentState(), .transcribing(liveText: "正在说更多"))
        engine.emitFinal("最终结果")
        drainMain()
        XCTAssertEqual(session.currentState(), .finished(text: "最终结果"))
    }

    func testCancelReturnsToIdleAndStopsRecorder() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        engine.emitPartial("x")
        drainMain()
        session.cancel()

        XCTAssertEqual(session.currentState(), .idle)
        XCTAssertTrue(recorder.stopCalled)
    }

    func testResetIsAliasForCancel() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        session.reset()

        XCTAssertEqual(session.currentState(), .idle)
    }

    func testStopIsNoOpWhenIdle() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        session.stop() // should not throw / not crash
        XCTAssertEqual(session.currentState(), .idle)
        XCTAssertEqual(recorder.stopCount, 0)
    }

    func testStartIsNoOpWhenAlreadyStarted() async {
        let engine = FakeASREngine()
        let recorder = FakeRecorder()
        let session = MobileDictationSession(engine: engine, recorder: recorder)

        await session.start()
        drainMain()
        let firstStartCount = recorder.startCount
        await session.start()
        drainMain()

        XCTAssertEqual(recorder.startCount, firstStartCount)
    }
}
