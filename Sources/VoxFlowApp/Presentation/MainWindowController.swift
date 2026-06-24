import AppKit
import SwiftUI
import VoxFlowTextInsertion

@MainActor
final class MainWindowController: NSWindowController {
    private let screenshotRecordViewModel: ScreenshotRecordViewModel

    init(
        environment: AppEnvironment,
        asrRuntime: AppASRRuntime,
        textRuntime: AppTextRuntime,
        audioCaptureCoordinator: AudioCaptureCoordinator,
        navigationRouter: WorkbenchNavigationRouter = WorkbenchNavigationRouter(),
        updatePromptStore: UpdatePromptPresentationStore = UpdatePromptPresentationStore(),
        onCheckForUpdates: @escaping () -> Void = {}
    ) {
        let viewModel = WorkbenchViewModel(environment: environment)
        let internalClipboardWriter = GeneralPasteboardWriter(
            internalWriteGuard: textRuntime.clipboardInternalWriteGuard
        )
        let homeViewModel = HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: internalClipboardWriter,
            outputService: textRuntime.outputService,
            targetProvider: WorkspaceDictationTargetProvider(),
            textPipeline: textRuntime.textPipeline
        )
        let voiceCorrectionViewModel = VoiceCorrectionViewModel(environment: environment)
        let styleViewModel = StyleViewModel(environment: environment)
        let llmProviderViewModel = LLMProviderViewModel(environment: environment)
        let asrProviderViewModel = ASRProviderViewModel(environment: environment, asrManager: asrRuntime.manager, registry: asrRuntime.registry)
        let settingsViewModel = SettingsViewModel(
            environment: environment,
            asrSettingsResetter: asrRuntime.manager,
            localModelDeletionCoordinator: asrRuntime.manager,
            clipboardWriter: internalClipboardWriter
        )
        let fileTranscriptionViewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: ASRFileTranscriptionWorker(asrManager: asrRuntime.manager),
            currentASRProviderID: { asrRuntime.manager.effectiveSelectedEngineType.providerID },
            clipboardWriter: internalClipboardWriter
        )
        let notesViewModel = NotesViewModel(
            environment: environment,
            transcriber: NotesRecordingService(
                asrManager: asrRuntime.manager,
                audioCaptureCoordinator: audioCaptureCoordinator
            )
        )
        let screenshotRecordViewModel = ScreenshotRecordViewModel(
            environment: environment,
            clipboardService: textRuntime.clipboardService
        )
        self.screenshotRecordViewModel = screenshotRecordViewModel
        let rootView = MainShellView(
            viewModel: viewModel,
            homeViewModel: homeViewModel,
            voiceCorrectionViewModel: voiceCorrectionViewModel,
            styleViewModel: styleViewModel,
            llmProviderViewModel: llmProviderViewModel,
            asrProviderViewModel: asrProviderViewModel,
            settingsViewModel: settingsViewModel,
            fileTranscriptionViewModel: fileTranscriptionViewModel,
            notesViewModel: notesViewModel,
            screenshotRecordViewModel: screenshotRecordViewModel,
            navigationRouter: navigationRouter,
            updatePromptStore: updatePromptStore,
            onCheckForUpdates: onCheckForUpdates
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
        window.sharingType = .readOnly
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

    func refreshScreenshotRecords() {
        screenshotRecordViewModel.refreshAfterExternalInsert()
    }
}
