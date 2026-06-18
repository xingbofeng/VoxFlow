public struct ASRFallbackRequest: Equatable, Sendable {
    public let originalProviderID: ASRProviderID
    public let fallbackProviderID: ASRProviderID

    public init(
        originalProviderID: ASRProviderID,
        fallbackProviderID: ASRProviderID
    ) {
        self.originalProviderID = originalProviderID
        self.fallbackProviderID = fallbackProviderID
    }
}

public struct ASRFallbackRecord: Equatable, Sendable {
    public let originalProviderID: ASRProviderID
    public let actualProviderID: ASRProviderID

    public init(
        originalProviderID: ASRProviderID,
        actualProviderID: ASRProviderID
    ) {
        self.originalProviderID = originalProviderID
        self.actualProviderID = actualProviderID
    }
}

public enum ASRFallbackDecision: Equatable, Sendable {
    case requiresConfirmation(ASRFallbackRequest)
    case allowed(ASRFallbackRecord)

    public var actualProviderIDForHUD: ASRProviderID? {
        switch self {
        case .requiresConfirmation:
            return nil
        case let .allowed(record):
            return record.actualProviderID
        }
    }
}

public enum ASRFallbackPolicy {
    public static func evaluate(
        originalProviderID: ASRProviderID,
        fallbackProviderID: ASRProviderID,
        userConfirmed: Bool
    ) -> ASRFallbackDecision {
        if userConfirmed {
            return .allowed(
                ASRFallbackRecord(
                    originalProviderID: originalProviderID,
                    actualProviderID: fallbackProviderID
                )
            )
        }

        return .requiresConfirmation(
            ASRFallbackRequest(
                originalProviderID: originalProviderID,
                fallbackProviderID: fallbackProviderID
            )
        )
    }
}
