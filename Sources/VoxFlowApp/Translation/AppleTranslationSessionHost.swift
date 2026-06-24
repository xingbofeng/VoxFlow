import AppKit
import SwiftUI
import Translation

/// 透明 SwiftUI host view，挂载 `.translationTask` 以获取系统 `TranslationSession`。
/// 将获得的 session 交给共享 coordinator 执行翻译请求。
/// host 本身透明、禁止命中测试，不干扰父视图的布局和事件。
struct AppleTranslationSessionHost: View {
    @ObservedObject var coordinator: AppleTranslationCoordinator

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .translationTask(coordinator.configuration) { session in
                let adapter = SystemAppleTranslationSessionAdapter(session: session)
                await coordinator.executePendingRequest(using: adapter)
            }
    }
}

extension View {
    /// 在视图根部挂载系统翻译 session host。
    /// host 透明、不拦截事件，仅提供 `.translationTask` 所需的可见视图上下文。
    func appleTranslationSessionHost(_ coordinator: AppleTranslationCoordinator) -> some View {
        background {
            AppleTranslationSessionHost(coordinator: coordinator)
        }
    }
}

/// NSView 工厂，供 AppKit 窗口（如截图框选 overlay）挂载系统翻译 host。
@MainActor
enum AppleTranslationSessionHostFactory {
    /// 创建一个不可见、禁止命中测试的 NSView，内含 SwiftUI host。
    /// 通过 `NSHostingView` 嵌入 `AppleTranslationSessionHost`。
    static func makeNSView(coordinator: AppleTranslationCoordinator) -> NSView {
        let hostView = NSHostingView(
            rootView: AppleTranslationSessionHost(coordinator: coordinator)
        )
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.isHidden = false
        // 禁止命中测试：不拦截截图 overlay 的鼠标事件
        hostView.appearance = NSAppearance(named: .aqua)
        return hostView
    }
}
