import AppKit
import SwiftUI
@preconcurrency import Translation
import VoxFlowTextInsertion

@MainActor
final class SelectionResultPanelController {
    private static let logger = AppLogger.general

    private let transformService: TextTransformService
    private let clipboard: any ClipboardSetting
    private let speech: any ScreenshotSpeechSpeaking
    private let textInserter: any TextInserting
    private let historyRecorder: any SelectionHistoryRecording
    private let panelController = TextResultPanelController(title: L10n.localize("selection.panel.title.result", comment: ""))
    private let translationCoordinator: AppleTranslationCoordinator

    init(
        transformService: TextTransformService,
        clipboard: any ClipboardSetting,
        speech: any ScreenshotSpeechSpeaking,
        textInserter: any TextInserting,
        translationCoordinator: AppleTranslationCoordinator,
        historyRecorder: any SelectionHistoryRecording = NoopSelectionHistoryRecorder()
    ) {
        self.transformService = transformService
        self.clipboard = clipboard
        self.speech = speech
        self.textInserter = textInserter
        self.translationCoordinator = translationCoordinator
        self.historyRecorder = historyRecorder
    }

    func present(
        selectedText: String,
        operation: TextTransformOperation
    ) {
        Self.logger.debug("SelectionResultPanelController present operation=\(operation) textLen=\(selectedText.count)")
        ContextBoostSuppression.setSuppressed(true, reason: Self.contextBoostSuppressionReason)

        let viewModel = SelectionResultViewModel(
            selectedText: selectedText,
            operation: operation,
            transformService: transformService,
            clipboard: clipboard,
            speech: speech,
            textInserter: textInserter,
            historyRecorder: historyRecorder
        )
        let rootView = SelectionResultPanelView(
            viewModel: viewModel,
            onClose: { [weak self, weak viewModel] in
                viewModel?.close()
                self?.close()
            }
        )

        panelController.present(
            rootView: rootView,
            accessoryView: AppleTranslationSessionHostFactory.makeNSView(coordinator: translationCoordinator),
            onCancel: { [weak self] in self?.close() }
        )
        viewModel.startTransformTask()
    }

    func close() {
        Self.logger.debug("SelectionResultPanelController close")
        ContextBoostSuppression.setSuppressed(false, reason: Self.contextBoostSuppressionReason)
        speech.stop()
        panelController.close()
    }

    private static let contextBoostSuppressionReason = "selection_result_panel"
}

private struct SelectionResultPanelView: View {
    @ObservedObject var viewModel: SelectionResultViewModel
    let onClose: () -> Void

    var body: some View {
        TextResultPanelShell(onClose: onClose) {
            TextResultPanelHeader(
                iconSystemName: viewModel.operation == .translation ? "translate" : "text.alignleft",
                title: title,
                statusMessage: viewModel.statusMessage,
                onClose: onClose
            )
        } tabs: {
            Picker("", selection: $viewModel.selectedTab) {
                Text(L10n.localize("selection.panel.tab.source", comment: "")).tag(SelectionResultTab.source)
                Text(L10n.localize("selection.panel.tab.result", comment: "")).tag(SelectionResultTab.result)
            }
        } content: {
            TextResultScrollableTextView(
                text: viewModel.displayedText,
                isPlaceholder: viewModel.displayedText.isEmpty,
                isLoading: viewModel.isTransforming && viewModel.selectedTab == .result
            )
        } playback: {
            if let playback = viewModel.playbackState {
                TextResultPlaybackBar(text: playback.text) {
                    viewModel.stopSpeaking()
                }
            }
        } footer: {
            TextResultFooterBar {
            Button {
                viewModel.speakSelectedText()
            } label: {
            Label(L10n.localize("selection.action.read", comment: ""), systemImage: "speaker.wave.2")
            }

            Button {
                viewModel.copySelectedText()
            } label: {
            Label(L10n.localize("selection.action.copy_text", comment: ""), systemImage: "doc.on.doc")
            }

            Button {
                Task { await viewModel.replaceOriginal() }
            } label: {
            Label(L10n.localize("selection.action.replace_source", comment: ""), systemImage: "text.cursor")
            }

            Button {
                Task { await viewModel.insertAfterSelection() }
            } label: {
            Label(L10n.localize("selection.action.insert_new_line", comment: ""), systemImage: "arrow.down.doc")
            }
        }
    }
    }

    private var title: String {
        switch viewModel.operation {
        case .translation:
            return L10n.localize("selection.panel.operation_title.translation", comment: "")
        case .summary:
            return L10n.localize("selection.panel.operation_title.summary", comment: "")
        }
    }

    private var resultTabTitle: String {
        switch viewModel.operation {
        case .translation:
            return L10n.localize("selection.panel.tab.translation", comment: "")
        case .summary:
            return L10n.localize("selection.panel.tab.summary", comment: "")
        }
    }
}
