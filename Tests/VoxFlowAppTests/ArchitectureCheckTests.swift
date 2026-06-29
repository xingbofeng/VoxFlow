import Foundation
import XCTest

final class ArchitectureCheckTests: XCTestCase {
    func testTextProcessingMasterToggleIsNotDisabledWithSubcontrols() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewURL = packageRoot
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)
        let masterTitleRange = try XCTUnwrap(
            source.range(of: "settings.text_processing.master.title")
        )
        let firstSubToggleRange = try XCTUnwrap(
            source.range(of: "settings.text_processing.smart_number.title")
        )
        let masterRowBody = source[masterTitleRange.lowerBound..<firstSubToggleRange.lowerBound]

        XCTAssertFalse(
            masterRowBody.contains(".disabled(!viewModel.deterministicTextProcessingEnabled)"),
            "The text-processing master switch must stay enabled when deterministic text processing is off."
        )
    }

    func testArchitectureCheckAcceptsAllowedFixture() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp", "VoxFlowProviderQwen3"])
        try fixture.writeSource(
            target: "VoxFlowProviderQwen3",
            file: "QwenRuntime.swift",
            contents: """
            import Foundation

            struct QwenRuntimeBoundary {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("architecture-check passed"), result.output)
    }

    func testArchitectureCheckRejectsProviderSwiftUIImport() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowProviderQwen3"])
        try fixture.writeSource(
            target: "VoxFlowProviderQwen3",
            file: "ProviderViewLeak.swift",
            contents: """
            import SwiftUI

            struct ProviderViewLeak {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Provider target must not import SwiftUI"),
            result.output
        )
    }

    func testArchitectureCheckRejectsProviderSwiftUIImportFromCustomTargetPath() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetPaths: [
            "VoxFlowProviderFoo": "Sources/VoxFlowProviders/VoxFlowProviderFoo",
        ])
        try fixture.writeSource(
            target: "VoxFlowProviders/VoxFlowProviderFoo",
            file: "ProviderViewLeak.swift",
            contents: """
            import SwiftUI

            struct ProviderViewLeak {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Sources/VoxFlowProviders/VoxFlowProviderFoo/ProviderViewLeak.swift"),
            result.output
        )
        XCTAssertTrue(
            result.output.contains("Provider target must not import SwiftUI"),
            result.output
        )
    }

    func testArchitectureCheckReportsScannedSwiftFileCounts() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetPaths: [
            "VoxFlowProviderFoo": "Sources/VoxFlowProviders/VoxFlowProviderFoo",
        ])
        try fixture.writeSource(
            target: "VoxFlowProviders/VoxFlowProviderFoo",
            file: "ProviderRuntime.swift",
            contents: """
            import Foundation

            struct ProviderRuntime {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("target VoxFlowProviderFoo: scanned 1 Swift files"),
            result.output
        )
    }

    func testArchitectureCheckRejectsProviderDatabaseAccess() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowProviderQwen3"])
        try fixture.writeSource(
            target: "VoxFlowProviderQwen3",
            file: "ProviderDatabaseLeak.swift",
            contents: """
            import Foundation

            final class ProviderDatabaseLeak {
                let queue: DatabaseQueue?
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Provider target must not access database primitives"),
            result.output
        )
    }

    func testArchitectureCheckRejectsProviderImportingAnotherProvider() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowProviderQwen3", "VoxFlowProviderWhisper"])
        try fixture.writeSource(
            target: "VoxFlowProviderQwen3",
            file: "ProviderCoupling.swift",
            contents: """
            import Foundation
            import VoxFlowProviderWhisper

            struct ProviderCoupling {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Provider target must not import provider target VoxFlowProviderWhisper"),
            result.output
        )
    }

    func testArchitectureCheckAllowsDeclaredProviderDependency() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetDeclarations: """
        .target(
            name: "VoxFlowProviderCloudCore",
            path: "Sources/VoxFlowProviderCloudCore"
        ),
        .target(
            name: "VoxFlowProviderGroq",
            dependencies: ["VoxFlowProviderCloudCore"],
            path: "Sources/VoxFlowProviderGroq"
        )
        """)
        try fixture.writeSource(
            target: "VoxFlowProviderGroq",
            file: "GroqClient.swift",
            contents: """
            import Foundation
            import VoxFlowProviderCloudCore

            struct GroqClient {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testArchitectureCheckAllowsProviderTestTargetImports() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetDeclarations: """
        .target(
            name: "VoxFlowProviderGroq",
            path: "Sources/VoxFlowProviderGroq"
        ),
        .testTarget(
            name: "VoxFlowProviderGroqTests",
            dependencies: ["VoxFlowProviderGroq"],
            path: "Tests/VoxFlowProviderGroqTests"
        )
        """)
        try fixture.writeSource(
            target: "../Tests/VoxFlowProviderGroqTests",
            file: "GroqClientTests.swift",
            contents: """
            import XCTest
            import VoxFlowProviderGroq

            final class GroqClientTests: XCTestCase {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testArchitectureCheckRejectsLocalizationFeatureImport() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowLocalization", "VoxFlowFeatures"])
        try fixture.writeSource(
            target: "VoxFlowLocalization",
            file: "FeatureLeak.swift",
            contents: """
            import Foundation
            import VoxFlowFeatures

            struct FeatureLeak {}
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Localization target must not import Feature target VoxFlowFeatures"),
            result.output
        )
    }

    func testArchitectureCheckRejectsUIModelPathAccess() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowFeatures"])
        try fixture.writeSource(
            target: "VoxFlowFeatures",
            file: "ModelPathLeak.swift",
            contents: """
            import Foundation

            struct ModelPathLeak {
                let path = ModelStorePaths.modelsDirectory
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("UI target must not access model store paths directly"),
            result.output
        )
    }

    func testArchitectureCheckRejectsUserVisibleHardcodedStringsInUITarget() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowFeatures"])
        try fixture.writeSource(
            target: "VoxFlowFeatures",
            file: "HardcodedCopy.swift",
            contents: """
            import SwiftUI

            struct HardcodedCopy: View {
                var body: some View {
                    Text("开始录音")
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("UI target must not hardcode user-visible strings"),
            result.output
        )
    }

    func testArchitectureCheckRejectsRuntimeBundleModuleAccess() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowScreenshotKit"])
        try fixture.writeSource(
            target: "VoxFlowScreenshotKit",
            file: "ScreenshotResourceLeak.swift",
            contents: """
            import Foundation

            enum ScreenshotResourceLeak {
                static let bundle = Bundle.module
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Runtime source must not use SwiftPM Bundle.module"),
            result.output
        )
    }

    func testArchitectureCheckRejectsViewModelStoredConcreteAppEnvironment() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ExampleViewModel.swift",
            contents: """
            import Foundation

            final class ExampleViewModel {
                private let environment: AppEnvironment

                init(environment: AppEnvironment) {
                    self.environment = environment
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ViewModel must depend on AppServiceProviding instead of concrete AppEnvironment"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectModelAvailabilityChecks() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AppKit

            final class AppDelegate {
                func isEnabled() -> Bool {
                    SherpaASRModelVariant.funASRInt8.modelsExist()
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must not perform direct model availability checks"),
            result.output
        )
    }

    func testArchitectureCheckRejectsASRManagerDirectFunASRLegacyEngine() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ASRManager.swift",
            contents: """
            final class ASRManager {
                func makeEngine(type: ASREngineType) -> ASREngine {
                    switch type {
                    case .funASR:
                        return SherpaBatchASREngine(variant: .funASRInt8)
                    default:
                        return SpeechRecognizer()
                    }
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ASRManager must build FunASR through provider-backed adapter"),
            result.output
        )
    }

    func testArchitectureCheckRejectsASRManagerDirectSenseVoiceLegacyEngine() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ASRManager.swift",
            contents: """
            final class ASRManager {
                func makeEngine(type: ASREngineType) -> ASREngine {
                    switch type {
                    case .senseVoice:
                        return FluidAudioBatchASREngine(model: .senseVoice)
                    default:
                        return SpeechRecognizer()
                    }
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ASRManager must build SenseVoice through provider-backed adapter"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppParaformerRuntimeImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "SherpaOnnxRuntime.swift",
            contents: """
            final class SherpaOnnxRecognizer {
                func makeConfig() {
                    _ = VOX_SHERPA_PARAFORMER
                    _ = SherpaASRModelVariant.paraformerEnglish
                    _ = ParaformerModels.modelsExist(at: modelURL, precision: .int8)
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not own Paraformer runtime, download, or selection implementation"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppSenseVoiceRuntimeImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "FluidAudioBatchASREngine.swift",
            contents: """
            final class FluidAudioBatchASREngine {
                func makeTranscriber() throws {
                    _ = try SenseVoiceModels.load(from: modelURL, precision: .fp16)
                    _ = SenseVoiceManager(models: models)
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not own SenseVoice runtime implementation"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectModelDownloadBranches() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AppKit

            final class AppDelegate {
                func downloadModel() async throws {
                    let downloader = Qwen3ModelDownloader.live()
                    _ = try await downloader.download(size: .size0_6B) { _ in }
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must not perform direct model downloads"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectRecordingPermissionPrimitives() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AppKit

            final class AppDelegate {
                func refresh() {
                    _ = AudioRecorder.checkPermission()
                    _ = SpeechRecognizer.checkPermission()
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must use RecordingPermissionService for recording permissions"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectASRStatePrimitives() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AppKit

            final class AppDelegate {
                private let asrManager = ASRManager()
                private lazy var resolver = ASRMenuStateResolver(asrManager: asrManager)
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must use ASRCoordinator for ASR state"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectMenuBarState() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AppKit

            final class AppDelegate: NSObject, NSMenuDelegate {
                private var languageMenuItems: [NSMenuItem] = []
                private func setupASREngineMenu() {}
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must use MenuBarCoordinator for status menu state"),
            result.output
        )
    }

    func testArchitectureCheckRejectsDictationOrchestratorDirectTextOutput() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "DictationOrchestrator.swift",
            contents: """
            final class DictationOrchestrator {
                private let textInjector: TextInjecting
                private let clipboardService: ClipboardSetting

                func deliverFinalText(_ text: String) async {
                    let result = await textInjector.inject(text)
                    if result == .permissionDenied {
                        clipboardService.setString(text)
                    }
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("DictationOrchestrator must deliver text through OutputService"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppRuntimePrewarmHooks() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            final class AppDelegate {
                private let modelPrewarmer = ASRModelPrewarmCenter.shared

                private func prewarmCurrentASREngine() {
                    modelPrewarmer.cancelPrewarming()
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not prewarm ASR runtime during app launch, model switch, or dictation start"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppClipboardImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "TextInjector.swift",
            contents: """
            import AppKit

            struct PasteboardTransaction {
                func restoreOriginalIfUnchanged(on pasteboard: NSPasteboard) -> Bool {
                    true
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not own clipboard transaction implementation"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppTextInsertionContract() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "DictationOrchestrator.swift",
            contents: """
            import Foundation

            enum InjectionResult {
                case success
            }

            protocol TextInjecting: AnyObject {
                func inject(_ text: String) async -> InjectionResult
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not own text insertion contract"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppFastPasteImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "TextInjector.swift",
            contents: """
            import Carbon

            final class TextInjector {
                func insert(_ text: String) async {
                    _ = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not own fast paste text insertion implementation"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppQwenStreamingRuntimeImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "Qwen3ASREngine.swift",
            contents: """
            final class Qwen3ASREngine {
                func start() async throws {
                    let driver = Qwen3StreamingRuntimeDriver(
                        modelURL: modelURL,
                        languageHint: "zh",
                        sessionFactory: sessionFactory
                    )
                    try await driver.start()
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp Qwen legacy adapter must not own streaming runtime implementation"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppQwenProviderConstructionInLegacyWrapper() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "Qwen3ASREngine.swift",
            contents: """
            final class Qwen3ASREngine {
                init(modelPath: String?) {
                    let readyModelURL = modelPath.flatMap {
                        Qwen3ModelManifest.supportedModelExists(at: URL(fileURLWithPath: $0)) ? URL(fileURLWithPath: $0) : nil
                    }
                    let provider = Qwen3ASRProvider(
                        descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
                        modelURL: readyModelURL
                    )
                    _ = provider
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp Qwen legacy adapter must delegate provider construction to VoxFlowProviderQwen3"),
            result.output
        )
    }

    func testArchitectureCheckRejectsASRManagerDirectQwenLegacyEngineConstruction() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ASRManager.swift",
            contents: """
            final class ASRManager {
                func makeEngine() -> Any {
                    Qwen3ASREngine(modelPath: "/tmp/model")
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ASRManager must build Qwen through provider-backed adapter"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppQwenReadinessRuntimeImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "Qwen3ModelReadinessPreparer.swift",
            contents: """
            import Foundation
            import VoxFlowModelStore

            struct Qwen3ModelReadinessPreparer {
                private let runner = ModelPrewarmCanaryRunner()

                func prepare() {
                    _ = Qwen3ModelRuntimePreparer()
                    _ = Qwen3ModelStoreMetadata.metadata
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp Qwen readiness adapter must delegate prewarm and canary to VoxFlowProviderQwen3"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppQwenDirectDownloadImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "Qwen3ModelDownloader.swift",
            contents: """
            import Foundation

            final class Qwen3ModelDownloader: NSObject, URLSessionDownloadDelegate {
                private var session: URLSession!

                func download(url: URL) {
                    session.downloadTask(with: url).resume()
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp Qwen downloader adapter must delegate download implementation to VoxFlowProviderQwen3 ModelStore"),
            result.output
        )
    }

    func testArchitectureCheckRejectsQwenStreamingDriverRuntimePrewarmAtStart() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowProviderQwen3"])
        try fixture.writeSource(
            target: "VoxFlowProviderQwen3",
            file: "Qwen3StreamingRuntimeDriver.swift",
            contents: """
            actor Qwen3StreamingRuntimeDriver {
                private var session: Qwen3StreamingSession?

                func start() async throws {
                    try await session?.prewarm()
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Qwen3 streaming driver start must not prewarm runtime without audio"),
            result.output
        )
    }

    func testArchitectureCheckRejectsVoxFlowAppWhisperRuntimeImplementation() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "WhisperKitBatchASREngine.swift",
            contents: """
            import WhisperKit

            final class WhisperKitBatchASREngine {
                func start() async throws {
                    _ = try await WhisperKit(WhisperKitConfig(modelFolder: "/tmp/whisper"))
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("VoxFlowApp must not own Whisper runtime implementation"),
            result.output
        )
    }

    func testArchitectureCheckRejectsSettingsWindowDirectQwenDownloaderConstruction() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "SettingsWindowController.swift",
            contents: """
            import AppKit

            final class SettingsWindowController {
                func download() {
                    let downloader = Qwen3ModelDownloader()
                    _ = downloader
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("SettingsWindowController must receive model download dependencies instead of constructing them"),
            result.output
        )
    }

    func testArchitectureCheckRejectsSettingsWindowDirectQwenManifestConstruction() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "SettingsWindowController.swift",
            contents: """
            import AppKit

            final class SettingsWindowController {
                func download() {
                    let manifest = Qwen3ModelManifest.manifest(for: .size0_6B)
                    _ = manifest
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("SettingsWindowController must delegate Qwen manifest creation to model download dependencies"),
            result.output
        )
    }

    func testArchitectureCheckRejectsSettingsWindowDirectASRManagerConstruction() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "SettingsWindowController.swift",
            contents: """
            import AppKit

            final class SettingsWindowController {
                private let asrManager = ASRManager()
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("SettingsWindowController must receive app-scoped ASR runtime dependencies instead of constructing ASRManager"),
            result.output
        )
    }

    func testArchitectureCheckRejectsASRProviderViewModelDirectQwenManifestConstruction() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ASRProviderViewModel.swift",
            contents: """
            import Foundation

            final class ASRProviderViewModel {
                func download() {
                    let manifest = Qwen3ModelManifest.manifest(for: .size0_6B)
                    _ = manifest
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ASRProviderViewModel must delegate Qwen manifest creation to model download dependencies"),
            result.output
        )
    }

    func testArchitectureCheckRejectsASRProviderViewModelDirectQwenDownloaderConstruction() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ASRProviderViewModel.swift",
            contents: """
            import Foundation

            final class ASRProviderViewModel {
                init(downloader: any Qwen3ModelDownloading = Qwen3ModelDownloader()) {}
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ASRProviderViewModel must receive Qwen model download dependencies from Qwen3ModelDownloader.live()"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectHUDUpdates() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            final class AppDelegate {
                private let overlayController: OverlayWindowController

                func handleState() {
                    overlayController.updateTranscription("text", isRefining: false)
                    overlayController.showTemporaryMessage("done", duration: 2.0)
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must use VoiceHUDFeatureController for HUD updates"),
            result.output
        )
    }

    func testArchitectureCheckRejectsAppDelegateDirectTextInputPrimitives() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AppKit

            final class AppDelegate {
                func inject(_ text: String) {
                    _ = PasteboardTransaction.begin(on: .general, replacementText: text)
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("AppDelegate must not perform direct text input or clipboard insertion"),
            result.output
        )
    }

    func testArchitectureCheckRejectsMainActorAudioBufferAppendFromRecorderDelegate() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "AppDelegate.swift",
            contents: """
            import AVFoundation

            final class AppDelegate: AudioRecorder.Delegate {
                nonisolated func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
                    let sendableBuffer = AudioRecorder.SendableBuffer(buffer: buffer)
                    Task { @MainActor [weak self, sendableBuffer] in
                        self?.dictationOrchestrator.appendAudioBuffer(sendableBuffer.buffer)
                    }
                }
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Audio recorder delegate must not hop to MainActor to append audio buffers"),
            result.output
        )
    }

    func testArchitectureCheckRejectsASREngineRawPCMBufferInput() throws {
        let fixture = try ArchitectureFixture()
        try fixture.writePackage(targetNames: ["VoxFlowApp"])
        try fixture.writeSource(
            target: "VoxFlowApp",
            file: "ASREngine.swift",
            contents: """
            import AVFoundation

            protocol ASREngine: AnyObject {
                func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
            }
            """
        )

        let result = try runArchitectureCheck(package: fixture.packageURL, sourceRoot: fixture.sourcesURL)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("ASREngine must accept AudioFrame instead of raw AVAudioPCMBuffer"),
            result.output
        )
    }

    func testMakefileExposesArchitectureCheckTarget() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("architecture-check:"), "Makefile must expose make architecture-check.")
        XCTAssertTrue(makefile.contains("scripts/architecture_check.py"), "Makefile must run the architecture checker script.")
    }

    func testMakefileExposesExplicitASRSmokeTargets() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("smoke-asr-provider:"), "Makefile must expose lightweight ASR provider smoke.")
        XCTAssertTrue(makefile.contains("smoke-asr-live:"), "Makefile must expose opt-in live ASR model smoke.")
        XCTAssertTrue(makefile.contains("$(SWIFT) test $(SWIFT_PACKAGE_FLAGS) --filter VoxFlowProviderSmokeTests"))
        XCTAssertTrue(makefile.contains("VOICEINPUT_TEST_ASR_SMOKE_PROVIDER=$(PROVIDER)"))
        XCTAssertTrue(makefile.contains("$(SWIFT) test $(SWIFT_PACKAGE_FLAGS) --filter ASRProviderLiveSmokeTests"))
    }

    func testCIExecutesArchitectureCheckBeforePackaging() throws {
        let ci = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(ci.contains("make architecture-check"), "CI must run architecture-check before package build.")
    }

    private func runArchitectureCheck(package: URL, sourceRoot: URL) throws -> (status: Int32, output: String) {
        let root = try Self.repositoryRoot()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            root.appendingPathComponent("scripts/architecture_check.py").path,
            "--package",
            package.path,
            "--source-root",
            sourceRoot.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ArchitectureCheckTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from current directory."]
        )
    }
}

private struct ArchitectureFixture {
    let rootURL: URL
    let packageURL: URL
    let sourcesURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchitectureCheckFixture-\(UUID().uuidString)", isDirectory: true)
        packageURL = rootURL.appendingPathComponent("Package.swift")
        sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
    }

    func writePackage(targetNames: [String]) throws {
        let targetDeclarations = targetNames
            .map { "        .target(name: \"\($0)\", path: \"Sources/\($0)\")" }
            .joined(separator: ",\n")
        try writePackage(targetDeclarations: targetDeclarations)
    }

    func writePackage(targetPaths: [String: String]) throws {
        let targetDeclarations = targetPaths
            .sorted { $0.key < $1.key }
            .map { "        .target(name: \"\($0.key)\", path: \"\($0.value)\")" }
            .joined(separator: ",\n")
        try writePackage(targetDeclarations: targetDeclarations)
    }

    func writePackage(targetDeclarations: String) throws {
        let contents = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "ArchitectureFixture",
            targets: [
        \(targetDeclarations)
            ]
        )
        """
        try contents.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    func writeSource(target: String, file: String, contents: String) throws {
        let directory = sourcesURL.appendingPathComponent(target, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(file)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
