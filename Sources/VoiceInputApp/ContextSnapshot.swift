import Foundation

// MARK: - ContextSource

enum ContextSource: String, Codable, Equatable {
    case windowMetadata
    case accessibilityVisibleText
    case accessibilitySelectedText
    case accessibilityInputArea
    case visualFallback
}

// MARK: - ContextSnapshot

struct ContextSnapshot: Equatable, Codable {
    let windowTitle: String?
    let targetAppBundleID: String?
    let targetAppName: String?
    let visibleText: String?
    let selectedText: String?
    let inputAreaText: String?
    let visualContentAvailable: Bool
    let sources: [ContextSource]
    let trimmedLength: Int
    let warnings: [String]

    init(
        windowTitle: String? = nil,
        targetAppBundleID: String? = nil,
        targetAppName: String? = nil,
        visibleText: String? = nil,
        selectedText: String? = nil,
        inputAreaText: String? = nil,
        visualContentAvailable: Bool = false,
        sources: [ContextSource] = [],
        trimmedLength: Int = 0,
        warnings: [String] = []
    ) {
        self.windowTitle = windowTitle
        self.targetAppBundleID = targetAppBundleID
        self.targetAppName = targetAppName
        self.visibleText = visibleText
        self.selectedText = selectedText
        self.inputAreaText = inputAreaText
        self.visualContentAvailable = visualContentAvailable
        self.sources = sources
        self.trimmedLength = trimmedLength
        self.warnings = warnings
    }

    /// Total character count of all text fields.
    var totalTextLength: Int {
        (visibleText?.count ?? 0)
            + (selectedText?.count ?? 0)
            + (inputAreaText?.count ?? 0)
    }

    /// Whether accessibility text is sufficient (>= 50 chars total).
    var hasAccessibilityContent: Bool {
        totalTextLength >= 50
    }
}
