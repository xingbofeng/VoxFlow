import XCTest
@testable import VoiceInputApp

final class ASRProviderRegistryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ASRManager!
    private var registry: ASRProviderRegistry!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.ASRProviderRegistry")!
        defaults.removePersistentDomain(forName: "test.ASRProviderRegistry")
        manager = ASRManager(defaults: defaults)
        registry = ASRProviderRegistry(asrManager: manager)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test.ASRProviderRegistry")
        super.tearDown()
    }

    func testBuiltInDescriptorsExposeCapabilitiesAndTags() throws {
        let apple = try XCTUnwrap(registry.descriptor(id: ASRProviderID.appleSpeech))
        let qwen = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertEqual(apple.displayName, "系统自带")
        XCTAssertTrue(apple.capabilities.contains(.streaming))
        XCTAssertTrue(apple.capabilities.contains(.punctuation))
        XCTAssertTrue(qwen.capabilities.contains(.local))
        XCTAssertTrue(qwen.capabilities.contains(.multilingual))
        XCTAssertTrue(qwen.tags.contains("本地"))
        XCTAssertEqual(qwen.statusMessage, "尚未安装本地模型")
        XCTAssertEqual(
            qwen.privacySummary,
            "请先下载模型，或选择已有的模型文件夹。语音仅在本机处理，不会上传。"
        )
    }

    func testFilteringByCapabilityAndTag() {
        let localProviders = registry.descriptors(
            matching: ASRProviderFilter(requiredCapabilities: [.local], tags: ["本地"])
        )

        XCTAssertEqual(localProviders.map(\.id), [ASRProviderID.qwen3])
    }

    func testDefaultProviderFallsBackToAppleWhenQwenModelIsMissing() throws {
        manager.selectedEngineType = .qwen3

        let defaultProvider = try registry.defaultProvider()
        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))
        let fallbackChain = registry.fallbackChain(startingAt: ASRProviderID.qwen3)

        XCTAssertTrue(qwenDescriptor.isDefault)
        XCTAssertEqual(defaultProvider.id, ASRProviderID.appleSpeech)
        XCTAssertEqual(fallbackChain.map(\.id), [ASRProviderID.appleSpeech])
    }

    func testDefaultProviderCanSelectAvailableQwenModel() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }
        manager.qwen3ModelPath = modelURL.path

        try registry.selectDefaultProvider(id: ASRProviderID.qwen3)

        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))
        XCTAssertEqual(try registry.defaultProvider().id, ASRProviderID.qwen3)
        XCTAssertEqual(manager.selectedEngineType, .qwen3)
        XCTAssertEqual(qwenDescriptor.statusMessage, "本地模型已就绪")
        XCTAssertEqual(qwenDescriptor.privacySummary, "语音仅在本机处理，不会上传。")
    }

    private func createLoadableQwen3ModelDirectory(at modelURL: URL) throws {
        for relativePath in Qwen3ModelManifest.requiredLoadablePaths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }
    }
}
