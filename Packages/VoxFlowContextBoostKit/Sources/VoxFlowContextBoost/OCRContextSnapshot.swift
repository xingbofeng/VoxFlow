import Foundation

public struct OCRContextSnapshot: Sendable, Codable, Equatable {
    public let bundleID: String?
    public let appName: String?
    public let windowTitle: String?
    public let capturedAt: Date
    public let ocrCharacterCount: Int?
    public let candidateCount: Int?
    public let hotwords: [TemporaryHotword]

    public init(
        bundleID: String?,
        appName: String?,
        windowTitle: String?,
        capturedAt: Date,
        hotwords: [TemporaryHotword],
        ocrCharacterCount: Int? = nil,
        candidateCount: Int? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.capturedAt = capturedAt
        self.ocrCharacterCount = ocrCharacterCount
        self.candidateCount = candidateCount
        self.hotwords = hotwords
    }
}
