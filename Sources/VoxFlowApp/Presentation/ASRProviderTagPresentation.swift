import Foundation

enum ASRProviderCardTag: String, CaseIterable {
    case offline
    case online
    case streaming
    case nonStreaming = "non_streaming"
    case fast
    case accurate
    case chinese
    case english
    case multilingual
    case coreML
    case hotwords

    var localizedTitle: String {
        switch self {
        case .offline:
            return L10n.localize("menu.provider_tag.offline", comment: "")
        case .online:
            return L10n.localize("menu.provider_tag.online", comment: "")
        case .streaming:
            return L10n.localize("menu.provider_tag.streaming", comment: "")
        case .nonStreaming:
            return L10n.localize("menu.provider_tag.non_streaming", comment: "")
        case .fast:
            return L10n.localize("menu.provider_tag.fast", comment: "")
        case .accurate:
            return L10n.localize("menu.provider_tag.accurate", comment: "")
        case .chinese:
            return L10n.localize("menu.provider_tag.chinese", comment: "")
        case .english:
            return L10n.localize("menu.provider_tag.english", comment: "")
        case .multilingual:
            return L10n.localize("menu.provider_tag.multilingual", comment: "")
        case .coreML:
            return L10n.localize("menu.provider_tag.coreml", comment: "")
        case .hotwords:
            return L10n.localize("provider.tag.hotwords", comment: "")
        }
    }
}

enum ASRProviderTagPresentation {
    static let approvedCardTags: [ASRProviderCardTag] = [
        .online,
        .offline,
        .streaming,
        .nonStreaming,
        .fast,
        .accurate,
        .chinese,
        .english,
        .multilingual,
        .hotwords,
        .coreML
    ]

    static func cardTags(for provider: ASRProviderDescriptor) -> [String] {
        var tags: [ASRProviderCardTag] = []

        if provider.capabilities.contains(.cloud) || provider.tags.contains("在线") || provider.externalLinks != nil {
            append(.online, to: &tags)
        } else {
            append(.offline, to: &tags)
        }
        if provider.capabilities.contains(.streaming) {
            append(.streaming, to: &tags)
        } else {
            append(.nonStreaming, to: &tags)
        }
        if provider.capabilities.contains(.fast) || provider.tags.contains("快速") {
            append(.fast, to: &tags)
        }
        if provider.capabilities.contains(.accurate) || provider.tags.contains("准确") {
            append(.accurate, to: &tags)
        }
        if containsChineseTag(provider.tags) {
            append(.chinese, to: &tags)
        }
        if containsEnglishTag(provider.tags) {
            append(.english, to: &tags)
        }
        if provider.capabilities.contains(.multilingual) || provider.tags.contains("多语言") {
            append(.multilingual, to: &tags)
        }
        if containsCoreMLTag(provider.tags) {
            append(.coreML, to: &tags)
        }
        if let engineType = provider.engineType,
           ASRHotwordCapabilityMatrix.capability(for: engineType).showsHotwordTag {
            append(.hotwords, to: &tags)
        }

        return tags.filter { approvedCardTags.contains($0) }.map(\.localizedTitle)
    }

    private static func append(_ tag: ASRProviderCardTag, to tags: inout [ASRProviderCardTag]) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private static func containsChineseTag(_ tags: [String]) -> Bool {
        tags.contains { tag in
            tag == "中文" || tag.localizedCaseInsensitiveContains("zh")
        }
    }

    private static func containsEnglishTag(_ tags: [String]) -> Bool {
        tags.contains { tag in
            tag == "英文"
                || tag == "English"
                || tag.localizedCaseInsensitiveContains("en-")
        }
    }

    private static func containsCoreMLTag(_ tags: [String]) -> Bool {
        tags.contains { tag in
            tag.localizedCaseInsensitiveCompare("CoreML") == .orderedSame
        }
    }
}
