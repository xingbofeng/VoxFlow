import XCTest
@testable import VoxFlowApp

final class AppDelegateASRMenuTests: XCTestCase {
    @MainActor
    func testASRMenuOptionsExposeEverySelectableLocalVariant() {
        let options = ASRMenuOptions.makeOptions()

        XCTAssertEqual(
            options.map(\.title),
            [
                "系统自带",
                "Groq",
                "腾讯云",
                "阿里云",
                "FunASR Nano INT8",
                "FunASR Nano FP32",
                "Whisper Turbo",
                "Whisper Large V3",
                "Qwen3-ASR 0.6B",
                "Qwen3-ASR 1.7B",
                "SenseVoice Small",
                "Paraformer Large zh",
                "NVIDIA Nemotron ASR 0.6B",
                "Parakeet Streaming",
                "Omnilingual ASR",
            ]
        )
    }

    @MainActor
    func testASRMenuOptionsExposeParaformerAsFormalProvider() {
        XCTAssertTrue(ASRMenuOptions.makeOptions().contains { $0.title.contains("Paraformer") })
    }

    @MainActor
    func testAppDelegateASRMenuOptionsBridgeUsesSharedOptions() {
        XCTAssertEqual(
            AppDelegate.makeASRMenuOptions().map(\.title),
            ASRMenuOptions.makeOptions().map(\.title)
        )
    }

    func testASRMenuStateResolverOwnsVariantAvailabilityAndSelection() {
        let suiteName = "test.ASRMenuStateResolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults, qwen3RuntimePreflight: { _ in .supported })
        let resolver = ASRMenuStateResolver(
            asrManager: manager,
            qwenAvailableOnDisk: { $0 == .size0_6B },
            funASRAvailable: { $0 == .fp32 },
            whisperAvailable: { $0 == .largeV3 }
        )
        let qwen06 = ASRMenuModel(engineType: .qwen3, modelSize: .size0_6B, title: "Qwen 0.6B")
        let qwen17 = ASRMenuModel(engineType: .qwen3, modelSize: .size1_7B, title: "Qwen 1.7B")
        let funASRFP32 = ASRMenuModel(engineType: .funASR, funASRPrecision: .fp32, title: "FunASR FP32")

        XCTAssertTrue(resolver.isEnabled(qwen06))
        XCTAssertFalse(resolver.isEnabled(qwen17))
        XCTAssertTrue(resolver.isEnabled(funASRFP32))

        XCTAssertTrue(resolver.select(qwen06))
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
        XCTAssertTrue(resolver.isSelected(qwen06))

        XCTAssertFalse(resolver.select(qwen17))
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
        XCTAssertTrue(resolver.isSelected(qwen06))

        XCTAssertTrue(resolver.select(funASRFP32))
        XCTAssertEqual(manager.funASRPrecision, .fp32)
        XCTAssertTrue(resolver.isSelected(funASRFP32))
    }

    func testASRMenuAllowsSupportedWhisperLargeButKeepsUnsupportedQwenDisabled() {
        let suiteName = "test.ASRMenuStateResolver.unsupported.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults) { size in
            size == .size1_7B
                ? .runtimeUnsupported(reason: "Qwen3-ASR 1.7B runtime unavailable.")
                : .supported
        }
        let resolver = ASRMenuStateResolver(
            asrManager: manager,
            qwenAvailableOnDisk: { _ in true },
            whisperAvailable: { _ in true }
        )
        let qwen17 = ASRMenuModel(engineType: .qwen3, modelSize: .size1_7B, title: "Qwen 1.7B")
        let whisperLarge = ASRMenuModel(
            engineType: .whisper,
            whisperVariant: .largeV3,
            title: "Whisper Large V3"
        )

        XCTAssertFalse(resolver.isEnabled(qwen17))
        XCTAssertFalse(resolver.select(qwen17))
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)

        XCTAssertTrue(resolver.isEnabled(whisperLarge))
        XCTAssertTrue(resolver.select(whisperLarge))
        XCTAssertEqual(manager.whisperVariant, .largeV3)
        XCTAssertEqual(manager.selectedEngineType, .whisper)
    }

    func testGroqMenuOptionIsDisabledUntilCredentialExists() throws {
        let suiteName = "test.ASRMenuStateResolver.groq.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = GroqMenuCredentialStore()
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        let resolver = ASRMenuStateResolver(asrManager: manager)
        let groq = ASRMenuModel(engineType: .groqWhisper, title: "Groq")

        XCTAssertFalse(resolver.isEnabled(groq))
        XCTAssertFalse(resolver.select(groq))

        try manager.saveGroqAPIKey("secret")

        XCTAssertTrue(resolver.isEnabled(groq))
        XCTAssertTrue(resolver.select(groq))
        XCTAssertTrue(resolver.isSelected(groq))
        XCTAssertEqual(manager.selectedEngineType, .groqWhisper)
    }

    @MainActor
    func testMenuOpeningRefreshesASRSelectionChangedOutsideMenu() {
        let tencent = ASRMenuModel(engineType: .tencentCloud, title: "腾讯云")
        let nvidia = ASRMenuModel(engineType: .nvidiaNemotron, title: "NVIDIA")
        var selectedEngine = ASREngineType.tencentCloud
        let coordinator = MenuBarCoordinator(
            asrOptions: [tencent, nvidia],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { option in option.engineType == selectedEngine },
            actions: .noop
        )
        let submenu = coordinator.menu.items
            .compactMap { $0.submenu }
            .first { $0.items.contains { $0.title == "腾讯云" } }

        XCTAssertEqual(submenu?.items.first { $0.title == "腾讯云" }?.state, .on)
        XCTAssertEqual(submenu?.items.first { $0.title == "NVIDIA" }?.state, .off)

        selectedEngine = .nvidiaNemotron
        coordinator.menuWillOpen(coordinator.menu)

        XCTAssertEqual(submenu?.items.first { $0.title == "腾讯云" }?.state, .off)
        XCTAssertEqual(submenu?.items.first { $0.title == "NVIDIA" }?.state, .on)
    }

    func testParaformerSelectionIsRepresentableAsMenuOption() {
        XCTAssertTrue(ASREngineType.allCases.map(\.rawValue).contains("Paraformer"))
    }
}

private final class GroqMenuCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
