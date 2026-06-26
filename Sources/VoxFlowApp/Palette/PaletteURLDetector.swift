import Foundation

/// 判断 Palette 输入是否为可打开 URL，并规范化为带 scheme 的 URL。
///
/// 规则：
/// - 含空白的输入视为普通查询词，不判为 URL。
/// - `http://` / `https://` 开头的输入保留原样，但须通过 host 校验。
/// - 裸域名补 `https://`；`localhost` 与 IPv4 补 `http://`。
/// - 裸 host 须为合法 localhost / IPv4 / 域名（TLD 纯字母且长度 2–6）。
enum PaletteURLDetector {
    /// 返回规范化后的 URL 字符串；不可打开的输入返回 nil。
    static func normalizedURL(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(where: { $0.isWhitespace }) { return nil }

        if hasScheme(trimmed) {
            return validSchemedURL(trimmed)
        }
        return normalizeBareURL(trimmed)
    }

    private static func hasScheme(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    private static func validSchemedURL(_ text: String) -> String? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        return text
    }

    private static func normalizeBareURL(_ text: String) -> String? {
        let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let hostPart = String(parts[0])
        let pathPart: String
        if parts.count > 1 {
            pathPart = "/" + String(parts[1])
        } else {
            pathPart = ""
        }

        guard let host = HostRecognizer.recognize(hostPart) else { return nil }
        return "\(host.scheme)://\(hostPart)\(pathPart)"
    }
}

private struct RecognizedHost {
    let scheme: String
}

private enum HostRecognizer {
    static func recognize(_ raw: String) -> RecognizedHost? {
        let host = splitPort(raw).host

        if host.lowercased() == "localhost" {
            return RecognizedHost(scheme: "http")
        }
        if isIPv4(host) {
            return RecognizedHost(scheme: "http")
        }
        if isDomain(host) {
            return RecognizedHost(scheme: "https")
        }
        return nil
    }

    private static func splitPort(_ raw: String) -> (host: String, port: String?) {
        if let colon = raw.lastIndex(of: ":") {
            let host = String(raw[..<colon])
            let port = String(raw[raw.index(after: colon)...])
            return (host, port)
        }
        return (raw, nil)
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return true
        }
    }

    private static func isDomain(_ text: String) -> Bool {
        let labels = text.split(separator: ".")
        guard labels.count >= 2 else { return false }
        guard let tld = labels.last,
              tld.allSatisfy({ $0.isLetter }),
              (2...6).contains(tld.count) else {
            return false
        }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { char in
                char.isLetter || char.isNumber || char == "-"
            }
        }
    }
}
