import AppKit
import SwiftUI

/// 问 AI 面板控制器。复用 `TextResultPanelController`（与划词翻译/总结结果面板同一右侧浮窗），
/// 在其中展示 `AIChatPanelView` 多轮聊天视图。
@MainActor
final class AIChatPanelController {
    private let panelController = TextResultPanelController(title: "问 AI")

    func present(viewModel: AIChatSessionViewModel, prompt: String) {
        let rootView = AIChatPanelView(
            viewModel: viewModel,
            onClose: { [weak self] in self?.close() }
        )
        panelController.present(
            rootView: rootView,
            contentSize: NSSize(width: 440, height: 560),
            onCancel: { [weak self] in self?.close() }
        )
        viewModel.send(prompt)
    }

    func close() {
        panelController.close()
    }
}
