import XCTest
import VoxFlowASRRuntime
import VoxFlowAudio
@testable import Mashangxie

final class ASRBridgeTests: XCTestCase {
    private var tempCredentialsURL: URL!

    override func setUp() {
        super.setUp()
        tempCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempCredentialsURL)
        super.tearDown()
    }

    func testStartBuildsEngineWithProviderAndLanguageThenForwardsAudioFrames() throws {
        let engine = FakeASREngine()
        let builder = FakeProviderEngineBuilder(engine: engine)
        let bridge = DictationASRBridge(engineBuilder: builder)

        try bridge.start(
            provider: .appleSpeech,
            language: .zhCN,
            onTranscription: { _, _ in },
            onError: { _ in }
        )
        let frame = makeFrame(sequenceNumber: 42)
        bridge.appendAudioFrame(frame)
        waitUntil { engine.appendedFrames.map(\.sequenceNumber) == [42] }

        XCTAssertEqual(builder.requestedProvider, .appleSpeech)
        XCTAssertEqual(builder.requestedLanguage, .zhCN)
        XCTAssertEqual(engine.startCallCount, 1)
        XCTAssertEqual(engine.appendedFrames.map(\.sequenceNumber), [42])
        XCTAssertTrue(bridge.isRunning)
    }

    func testPartialAndFinalCallbacksAreForwarded() throws {
        let engine = FakeASREngine()
        let bridge = DictationASRBridge(engineBuilder: FakeProviderEngineBuilder(engine: engine))
        var events: [(String, Bool)] = []

        try bridge.start(
            provider: .tencent,
            language: .zhCN,
            onTranscription: { events.append(($0, $1)) },
            onError: { _ in XCTFail("Unexpected error callback") }
        )

        engine.onTranscription?("你好", false)
        engine.onTranscription?("你好世界", true)

        XCTAssertEqual(events.map(\.0), ["你好", "你好世界"])
        XCTAssertEqual(events.map(\.1), [false, true])
    }

    func testErrorCallbackIsForwarded() throws {
        let engine = FakeASREngine()
        let bridge = DictationASRBridge(engineBuilder: FakeProviderEngineBuilder(engine: engine))
        var receivedError: String?

        try bridge.start(
            provider: .aliyun,
            language: .zhCN,
            onTranscription: { _, _ in XCTFail("Unexpected transcription callback") },
            onError: { receivedError = $0.localizedDescription }
        )

        engine.onError?(SampleASRError(message: "network down"))

        XCTAssertEqual(receivedError, "network down")
    }

    func testStopCancelAndEndAudioMapToUnderlyingEngine() throws {
        let engine = FakeASREngine()
        let bridge = DictationASRBridge(engineBuilder: FakeProviderEngineBuilder(engine: engine))

        try bridge.start(
            provider: .volcengine,
            language: .zhCN,
            onTranscription: { _, _ in },
            onError: { _ in }
        )
        bridge.endAudio()
        bridge.stop()
        waitUntil { engine.endAudioCallCount == 1 && engine.stopCallCount == 1 && !bridge.isRunning }

        XCTAssertEqual(engine.endAudioCallCount, 1)
        XCTAssertEqual(engine.stopCallCount, 1)
        XCTAssertFalse(bridge.isRunning)

        try bridge.start(
            provider: .volcengine,
            language: .zhCN,
            onTranscription: { _, _ in },
            onError: { _ in }
        )
        bridge.cancel()
        waitUntil { engine.cancelCallCount == 1 && !bridge.isRunning }

        XCTAssertEqual(engine.cancelCallCount, 1)
        XCTAssertFalse(bridge.isRunning)
    }

    func testUnavailableProviderThrowsBeforeStartingEngine() {
        let engine = FakeASREngine()
        engine.isAvailable = false
        let bridge = DictationASRBridge(engineBuilder: FakeProviderEngineBuilder(engine: engine))

        XCTAssertThrowsError(try bridge.start(
            provider: .appleSpeech,
            language: .zhCN,
            onTranscription: { _, _ in },
            onError: { _ in }
        )) { error in
            XCTAssertEqual(error as? ASRBridgeError, .providerUnavailable)
        }
        XCTAssertEqual(engine.startCallCount, 0)
        XCTAssertFalse(bridge.isRunning)
    }

    func testBuilderErrorSurfacesMissingCredentialFailure() {
        let builder = FakeProviderEngineBuilder(
            error: iOSASREngineFactory.FactoryError.missingCredential(provider: "腾讯云")
        )
        let bridge = DictationASRBridge(engineBuilder: builder)

        XCTAssertThrowsError(try bridge.start(
            provider: .tencent,
            language: .zhCN,
            onTranscription: { _, _ in },
            onError: { _ in }
        )) { error in
            XCTAssertEqual(error.localizedDescription, "腾讯云 凭证不完整，请在服务页填写。")
        }
    }

    func testConfiguredCloudProvidersBuildAvailableEngines() throws {
        let store = LocalCredentialStore(fileURL: tempCredentialsURL)

        try store.save(provider: .tencent, values: [
            "appID": "tencent-app-id",
            "secretID": "tencent-secret-id",
            "secretKey": "tencent-secret-key",
        ])
        try store.save(provider: .aliyun, values: [
            "apiKey": "aliyun-api-key",
        ])
        try store.save(provider: .volcengine, values: [
            "appID": "volcengine-app-id",
            "accessToken": "volcengine-access-token",
            "secretKey": "volcengine-secret-key",
        ])

        XCTAssertTrue(try iOSASREngineFactory.makeTencentEngine(store: store).isAvailable)
        XCTAssertTrue(try iOSASREngineFactory.makeAliyunEngine(store: store).isAvailable)
        XCTAssertTrue(try iOSASREngineFactory.makeVolcengineEngine(store: store).isAvailable)
    }

    private func makeFrame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray([0.1, -0.1]),
            sampleRate: 16_000,
            capturedAt: ContinuousClock().now
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Condition was not satisfied within \(timeout)s", file: file, line: line)
    }
}

private final class FakeProviderEngineBuilder: ProviderEngineBuilding {
    var requestedProvider: SelectedProvider?
    var requestedLanguage: SelectedLanguage?
    private let engine: FakeASREngine?
    private let error: Error?

    init(engine: FakeASREngine? = nil, error: Error? = nil) {
        self.engine = engine
        self.error = error
    }

    func makeEngine(for provider: SelectedProvider, language: SelectedLanguage) throws -> ASREngine {
        requestedProvider = provider
        requestedLanguage = language
        if let error {
            throw error
        }
        return engine ?? FakeASREngine()
    }
}

private final class FakeASREngine: ASREngine {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var isAvailable = true
    var configuredLocale: Locale?
    private let lock = NSLock()
    private var _startCallCount = 0
    private var _endAudioCallCount = 0
    private var _stopCallCount = 0
    private var _cancelCallCount = 0
    private var _appendedFrames: [AudioFrame] = []

    var startCallCount: Int { lock.withLock { _startCallCount } }
    var endAudioCallCount: Int { lock.withLock { _endAudioCallCount } }
    var stopCallCount: Int { lock.withLock { _stopCallCount } }
    var cancelCallCount: Int { lock.withLock { _cancelCallCount } }
    var appendedFrames: [AudioFrame] { lock.withLock { _appendedFrames } }

    func configure(locale: Locale) {
        configuredLocale = locale
    }

    func start() throws {
        lock.withLock { _startCallCount += 1 }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        lock.withLock { _appendedFrames.append(frame) }
    }

    func endAudio() {
        lock.withLock { _endAudioCallCount += 1 }
    }

    func stop() {
        lock.withLock { _stopCallCount += 1 }
    }

    func cancel() {
        lock.withLock { _cancelCallCount += 1 }
    }
}

private struct SampleASRError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
