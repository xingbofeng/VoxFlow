enum SmartConfigurationText {
    static func discoveredAppCount(_ count: Int) -> String {
        L10n.Localizable.Smart.Config.discoveredFormat(count)
    }

    static func appliedRecommendationCount(_ count: Int) -> String {
        L10n.Localizable.Smart.Config.actionAppliedFormat(count)
    }

    static func groupAppCount(_ count: Int) -> String {
        L10n.Localizable.Smart.Config.appCountFormat(count)
    }
}
