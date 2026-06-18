public enum ContextSource: String, Codable, Equatable, Sendable {
    case windowMetadata
    case accessibilityVisibleText
    case accessibilitySelectedText
    case accessibilityInputArea
    case visualFallback
}

public struct ContextSnapshot: Equatable, Codable, Sendable {
    public let windowTitle: String?
    public let targetAppBundleID: String?
    public let targetAppName: String?
    public let visibleText: String?
    public let selectedText: String?
    public let inputAreaText: String?
    public let visualContentAvailable: Bool
    public let sources: [ContextSource]
    public let trimmedLength: Int
    public let warnings: [String]

    public init(
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

    public var totalTextLength: Int {
        (visibleText?.count ?? 0)
            + (selectedText?.count ?? 0)
            + (inputAreaText?.count ?? 0)
    }

    public var hasAccessibilityContent: Bool {
        totalTextLength >= 50
    }
}
