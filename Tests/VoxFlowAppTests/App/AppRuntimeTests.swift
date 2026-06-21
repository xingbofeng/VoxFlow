import XCTest
@testable import VoxFlowApp

@MainActor
final class AppRuntimeTests: XCTestCase {
    func testBootstrapBuildsCoreRuntimeFromContainerFactory() throws {
        let container = try DependencyContainer.inMemory()

        let runtime = AppRuntime.bootstrap(containerFactory: { container })

        XCTAssertEqual(runtime.environment.storageHealth, container.storageHealth)
        XCTAssertEqual(
            runtime.asrCoordinator.dictationConfiguration(for: .simplifiedChinese).engineType,
            .apple
        )
        XCTAssertFalse(runtime.llmRefiner.isConfigured)
    }

    func testBootstrapFallsBackToUnavailableInMemoryRuntimeWhenLiveContainerFails() {
        let runtime = AppRuntime.bootstrap(containerFactory: {
            throw NSError(
                domain: "AppRuntimeTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "disk locked"]
            )
        })

        XCTAssertEqual(
            runtime.environment.storageHealth,
            .unavailable(reason: "Persistent storage failed to initialize: disk locked")
        )
        XCTAssertFalse(runtime.environment.storageHealth.isPersistent)
    }

    func testWindowCompositionReceivesAppScopedASRRuntime() throws {
        let root = try Self.repositoryRoot()
        let appRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppRuntime.swift"),
            encoding: .utf8
        )
        let windowCoordinator = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"),
            encoding: .utf8
        )
        let mainWindow = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/MainWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appRuntime.contains("let asrRuntime: AppASRRuntime"))
        XCTAssertTrue(appRuntime.contains("let textRuntime: AppTextRuntime"))
        XCTAssertTrue(appRuntime.contains("let audioCaptureCoordinator: AudioCaptureCoordinator"))
        XCTAssertTrue(windowCoordinator.contains("asrRuntime: AppASRRuntime"))
        XCTAssertTrue(windowCoordinator.contains("textRuntime: AppTextRuntime"))
        XCTAssertTrue(windowCoordinator.contains("audioCaptureCoordinator: AudioCaptureCoordinator"))
        XCTAssertTrue(mainWindow.contains("textRuntime: AppTextRuntime"))
        XCTAssertFalse(mainWindow.contains("RepositoryBackedLLMRefiner("))
        XCTAssertFalse(mainWindow.contains("DefaultOutputService("))
        XCTAssertFalse(mainWindow.contains("DefaultTextProcessingPipeline("))
        XCTAssertTrue(mainWindow.contains("ASRProviderViewModel(environment: environment, asrManager: asrRuntime.manager, registry: asrRuntime.registry)"))
        XCTAssertTrue(mainWindow.contains("worker: ASRFileTranscriptionWorker(asrManager: asrRuntime.manager)"))
        XCTAssertTrue(mainWindow.contains("currentASRProviderID: { asrRuntime.manager.effectiveSelectedEngineType.providerID }"))
        XCTAssertTrue(mainWindow.contains("NotesRecordingService("))
        XCTAssertTrue(mainWindow.contains("asrManager: asrRuntime.manager"))
        XCTAssertTrue(mainWindow.contains("audioCaptureCoordinator: audioCaptureCoordinator"))
        XCTAssertFalse(mainWindow.contains("NotesRecordingService()"))
        XCTAssertFalse(mainWindow.contains("FileTranscriptionViewModel(environment: environment)"))
    }

    func testAppDelegateUsesRuntimeOwnedLongLivedServices() throws {
        let root = try Self.repositoryRoot()
        let appRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppRuntime.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appRuntime.contains("let capabilityModelDownloader: SoniqoCapabilityModelDownloader"))
        XCTAssertTrue(appRuntime.contains("let screenshotOCRService: ScreenshotOCRService"))
        XCTAssertTrue(appRuntime.contains("let voiceTaskCoordinator: VoiceTaskCoordinator"))
        XCTAssertTrue(appRuntime.contains("let agentHelperManager: AgentHelperManager?"))
        XCTAssertFalse(appDelegate.contains("private let capabilityModelDownloader = SoniqoCapabilityModelDownloader()"))
        XCTAssertFalse(appDelegate.contains("ScreenshotOCRService("))
        XCTAssertFalse(appDelegate.contains("VoiceTaskCoordinator("))
        XCTAssertFalse(appDelegate.contains("AgentHelperManager(paths: paths)"))
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
            domain: "AppRuntimeTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift."]
        )
    }
}
