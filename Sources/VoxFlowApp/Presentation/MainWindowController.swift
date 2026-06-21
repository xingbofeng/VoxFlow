import AppKit
import SwiftUI
import VoxFlowTextInsertion

@MainActor
final class MainWindowController: NSWindowController {
    init(
        environment: AppEnvironment,
        asrRuntime: AppASRRuntime,
        textRuntime: AppTextRuntime,
        audioCaptureCoordinator: AudioCaptureCoordinator,
        navigationRouter: WorkbenchNavigationRouter = WorkbenchNavigationRouter()
    ) {
        let viewModel = WorkbenchViewModel(environment: environment)
        let homeViewModel = HomeDashboardViewModel(
            environment: environment,
            outputService: textRuntime.outputService,
            targetProvider: WorkspaceDictationTargetProvider(),
            textPipeline: textRuntime.textPipeline
        )
        let glossaryViewModel = GlossaryViewModel(environment: environment)
        let voiceCorrectionViewModel = VoiceCorrectionViewModel(environment: environment)
        let styleViewModel = StyleViewModel(environment: environment)
        let llmProviderViewModel = LLMProviderViewModel(environment: environment)
        let asrProviderViewModel = ASRProviderViewModel(environment: environment, asrManager: asrRuntime.manager, registry: asrRuntime.registry)
        let settingsViewModel = SettingsViewModel(
            environment: environment,
            asrSettingsResetter: asrRuntime.manager,
            localModelDeletionCoordinator: asrRuntime.manager
        )
        let fileTranscriptionViewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: ASRFileTranscriptionWorker(asrManager: asrRuntime.manager),
            currentASRProviderID: { asrRuntime.manager.effectiveSelectedEngineType.providerID }
        )
        let notesViewModel = NotesViewModel(
            environment: environment,
            transcriber: NotesRecordingService(
                asrManager: asrRuntime.manager,
                audioCaptureCoordinator: audioCaptureCoordinator
            )
        )
        let rootView = MainShellView(
            viewModel: viewModel,
            homeViewModel: homeViewModel,
            glossaryViewModel: glossaryViewModel,
            voiceCorrectionViewModel: voiceCorrectionViewModel,
            styleViewModel: styleViewModel,
            llmProviderViewModel: llmProviderViewModel,
            asrProviderViewModel: asrProviderViewModel,
            settingsViewModel: settingsViewModel,
            fileTranscriptionViewModel: fileTranscriptionViewModel,
            notesViewModel: notesViewModel,
            navigationRouter: navigationRouter
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_260, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ProductBrand.chineseDisplayName
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setFrame(
                WindowPlacementPolicy.centeredFrame(
                    windowSize: window.frame.size,
                    visibleFrame: visibleFrame
                ),
                display: false,
                animate: false
            )
        } else {
            window.center()
        }
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
