import Foundation

enum ASRProviderTagPresentation {
    static let approvedCardTags: [String] = [
        "离线",
        "在线",
        "流式",
        "非流式",
        "快速",
        "准确",
        "中文",
        "英文",
        "多语言",
        "CoreML",
    ]

    static func cardTags(for provider: ASRProviderDescriptor) -> [String] {
        var tags: [String] = []

        if provider.capabilities.contains(.cloud) || provider.tags.contains("在线") || provider.externalLinks != nil {
            append("在线", to: &tags)
        } else {
            append("离线", to: &tags)
        }
        if provider.capabilities.contains(.streaming) {
            append("流式", to: &tags)
        } else {
            append("非流式", to: &tags)
        }
        if provider.capabilities.contains(.fast) || provider.tags.contains("快速") {
            append("快速", to: &tags)
        }
        if provider.capabilities.contains(.accurate) || provider.tags.contains("准确") {
            append("准确", to: &tags)
        }
        if containsChineseTag(provider.tags) {
            append("中文", to: &tags)
        }
        if containsEnglishTag(provider.tags) {
            append("英文", to: &tags)
        }
        if provider.capabilities.contains(.multilingual) || provider.tags.contains("多语言") {
            append("多语言", to: &tags)
        }
        if containsCoreMLTag(provider.tags) {
            append("CoreML", to: &tags)
        }

        return tags.filter { approvedCardTags.contains($0) }
    }

    private static func append(_ tag: String, to tags: inout [String]) {
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
