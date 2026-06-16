import SwiftUI

enum ActionFeedbackTone: Equatable {
    case success
    case informational
    case destructive
}

enum ActionFeedbackLayout {
    static let maxWidth: CGFloat = 340
    static let topPadding: CGFloat = 18
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let shadowRadius: CGFloat = 10
    static let shadowYOffset: CGFloat = 4
}

enum ActionFeedbackContent: Equatable {
    case error(String)
    case message(String)
    case none

    static func resolve(message: String?, error: String?) -> ActionFeedbackContent {
        if let error {
            return .error(error)
        }
        if let message {
            return .message(message)
        }
        return .none
    }
}

struct ActionFeedbackView: View {
    let message: String?
    let error: String?
    var tone: ActionFeedbackTone = .success
    var autoDismissAfter: TimeInterval? = 2.6
    var onDismiss: (() -> Void)?

    var body: some View {
        Group {
            switch content {
            case .error(let error):
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .feedbackStyle(color: .red)
            case .message(let message):
                Label(message, systemImage: iconName)
                    .feedbackStyle(color: color)
            case .none:
                EmptyView()
            }
        }
        .task(id: feedbackKey) {
            guard let activeKey = feedbackKey else { return }
            guard let autoDismissAfter else { return }
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            if feedbackKey == activeKey {
                onDismiss?()
            }
        }
    }

    private var content: ActionFeedbackContent {
        ActionFeedbackContent.resolve(message: message, error: error)
    }

    private var feedbackKey: String? {
        error ?? message
    }

    private var iconName: String {
        switch tone {
        case .success:
            return "checkmark.circle.fill"
        case .informational:
            return "checkmark.circle.fill"
        case .destructive:
            return "trash.circle.fill"
        }
    }

    private var color: Color {
        switch tone {
        case .success:
            return AppTheme.ColorToken.accent
        case .informational:
            return AppTheme.ColorToken.accent
        case .destructive:
            return .red
        }
    }
}

private extension View {
    func feedbackStyle(color: Color) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: ActionFeedbackLayout.maxWidth, alignment: .leading)
            .padding(.horizontal, ActionFeedbackLayout.horizontalPadding)
            .padding(.vertical, ActionFeedbackLayout.verticalPadding)
            .background(AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: ActionFeedbackLayout.cornerRadius, style: .continuous)
                    .stroke(color.opacity(0.28))
            )
            .clipShape(RoundedRectangle(cornerRadius: ActionFeedbackLayout.cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(0.08),
                radius: ActionFeedbackLayout.shadowRadius,
                y: ActionFeedbackLayout.shadowYOffset
            )
    }
}

extension View {
    func actionFeedbackOverlay(
        message: String?,
        error: String?,
        tone: ActionFeedbackTone = .success,
        enabled: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        self.overlay(alignment: .top) {
            if enabled {
                ActionFeedbackView(
                    message: message,
                    error: error,
                    tone: tone,
                    onDismiss: onDismiss
                )
                .padding(.top, ActionFeedbackLayout.topPadding)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
        }
    }
}
