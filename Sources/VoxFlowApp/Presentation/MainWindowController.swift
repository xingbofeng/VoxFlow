import AppKit
import SwiftUI
import VoxFlowTextInsertion

@MainActor
final class MainWindowController: NSWindowController {
    init(environment: AppEnvironment) {
        let viewModel = WorkbenchViewModel(environment: environment)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore
        )
        let styleSelector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: LLMApplicationStyleClassifier(refiner: refiner)
        )
        let outputService = DefaultOutputService(
            textInsertionCoordinator: TextInsertionCoordinator(
                fastPasteInserter: FastPasteTextInserter()
            ),
            clipboardService: SystemClipboardService()
        )
        let homeViewModel = HomeDashboardViewModel(
            environment: environment,
            outputService: outputService,
            targetProvider: WorkspaceDictationTargetProvider(),
            textPipeline: DefaultTextProcessingPipeline(
                refiner: refiner,
                replacementRuleRepository: environment.replacementRuleRepository,
                glossaryRepository: environment.glossaryRepository,
                styleSelector: styleSelector
            )
        )
        let glossaryViewModel = GlossaryViewModel(environment: environment)
        let styleViewModel = StyleViewModel(environment: environment)
        let llmProviderViewModel = LLMProviderViewModel(environment: environment)
        let asrProviderViewModel = ASRProviderViewModel(environment: environment)
        let settingsViewModel = SettingsViewModel(environment: environment)
        let fileTranscriptionViewModel = FileTranscriptionViewModel(environment: environment)
        let notesViewModel = NotesViewModel(
            environment: environment,
            transcriber: NotesRecordingService()
        )
        let rootView = MainShellView(
            viewModel: viewModel,
            homeViewModel: homeViewModel,
            glossaryViewModel: glossaryViewModel,
            styleViewModel: styleViewModel,
            llmProviderViewModel: llmProviderViewModel,
            asrProviderViewModel: asrProviderViewModel,
            settingsViewModel: settingsViewModel,
            fileTranscriptionViewModel: fileTranscriptionViewModel,
            notesViewModel: notesViewModel
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
