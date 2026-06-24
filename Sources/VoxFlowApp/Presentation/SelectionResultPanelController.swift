import AppKit
import SwiftUI
import VoxFlowTextInsertion

@MainActor
final class SelectionResultPanelController {
    private static let logger = AppLogger.general

    private let transformService: TextTransformService
    private let clipboard: any ClipboardSetting
    private let speech: any ScreenshotSpeechSpeaking
    private let textInserter: any TextInserting
    private let historyRecorder: any SelectionHistoryRecording
    private let panelController = TextResultPanelController(title: "文本结果")

    init(
        transformService: TextTransformService,
        clipboard: any ClipboardSetting,
        speech: any ScreenshotSpeechSpeaking,
        textInserter: any TextInserting,
        historyRecorder: any SelectionHistoryRecording = NoopSelectionHistoryRecorder()
    ) {
        self.transformService = transformService
        self.clipboard = clipboard
        self.speech = speech
        self.textInserter = textInserter
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
                Text("原文").tag(SelectionResultTab.source)
                Text(resultTabTitle).tag(SelectionResultTab.result)
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
                Label("朗读", systemImage: "speaker.wave.2")
            }

            Button {
                viewModel.copySelectedText()
            } label: {
                Label("复制文字", systemImage: "doc.on.doc")
            }

            Button {
                Task { await viewModel.replaceOriginal() }
            } label: {
                Label("替换原文", systemImage: "text.cursor")
            }

            Button {
                Task { await viewModel.insertAfterSelection() }
            } label: {
                Label("插入下一行", systemImage: "arrow.down.doc")
            }
        }
    }
    }

    private var title: String {
        switch viewModel.operation {
        case .translation:
            return "划词翻译"
        case .summary:
            return "划词总结"
        }
    }

    private var resultTabTitle: String {
        switch viewModel.operation {
        case .translation:
            return "翻译"
        case .summary:
            return "总结"
        }
    }
}
