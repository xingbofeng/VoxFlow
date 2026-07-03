import Foundation

extension BuiltinAgentToolHost {
    func webFetch(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let urlString = requiredString("url", in: call),
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.user == nil,
              url.password == nil else {
            return .failure(toolName: call.name, code: "invalid_url")
        }
        guard Self.userExplicitlyMentionedWebURL(url, instruction: environment.userInstruction) || Self.isPreapprovedWebFetchURL(url) else {
            return .failure(toolName: call.name, code: "missing_explicit_user_intent")
        }

        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("text/markdown, text/html, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("VoxFlow-Agent/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await environment.httpClient(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(toolName: call.name, code: "invalid_response")
            }

            if (300..<400).contains(httpResponse.statusCode),
               let redirect = redirectURL(from: httpResponse, originalURL: url),
               !Self.isPermittedWebFetchRedirect(from: url, to: redirect) {
                let statusText = webFetchStatusText(httpResponse.statusCode)
                let message = """
                REDIRECT DETECTED: The URL redirects to a different host.

                Original URL: \(url.absoluteString)
                Redirect URL: \(redirect.absoluteString)
                Status: \(httpResponse.statusCode) \(statusText)

                To complete your request, use web_fetch again with the redirect URL.
                """
                return .success(
                    toolName: call.name,
                    result: [
                        "bytes": .int(message.utf8.count),
                        "code": .int(httpResponse.statusCode),
                        "codeText": .string(statusText),
                        "result": .string(message),
                        "durationMs": .int(Int(Date().timeIntervalSince(start) * 1_000)),
                        "url": .string(url.absoluteString)
                    ]
                )
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let rawText = String(data: data, encoding: .utf8) ?? ""
            let extracted = markdownLikeText(from: rawText, contentType: contentType)
            return .success(
                toolName: call.name,
                result: [
                    "bytes": .int(data.count),
                    "code": .int(httpResponse.statusCode),
                    "codeText": .string(webFetchStatusText(httpResponse.statusCode)),
                    "result": .string(extracted.truncated(limit: 100_000)),
                    "durationMs": .int(Int(Date().timeIntervalSince(start) * 1_000)),
                    "url": .string(url.absoluteString)
                ]
            )
        } catch {
            return .failure(toolName: call.name, code: "web_fetch_failed", message: error.localizedDescription)
        }
    }

    private func redirectURL(from response: HTTPURLResponse, originalURL: URL) -> URL? {
        guard let location = response.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: location, relativeTo: originalURL)?.absoluteURL
    }

    private func markdownLikeText(from rawText: String, contentType: String) -> String {
        guard contentType.localizedCaseInsensitiveContains("html") || rawText.localizedCaseInsensitiveContains("<html") else {
            return rawText
        }
        var text = rawText
        text = text.replacingOccurrences(
            of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#,
            with: "",
            options: .regularExpression
        )
        for level in 1...6 {
            let tag = "h\(level)"
            text = text.replacingOccurrences(
                of: "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)>",
                with: String(repeating: "#", count: level) + " $1\n",
                options: .regularExpression
            )
        }
        text = text.replacingOccurrences(of: #"(?is)</p\s*>"#, with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: #"(?m)[ \t]+$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func webFetchStatusText(_ statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 303: "See Other"
        case 307: "Temporary Redirect"
        case 308: "Permanent Redirect"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        default: HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
        }
    }

    static func userExplicitlyMentionedWebURL(_ url: URL, instruction: String) -> Bool {
        instruction.lowercased().contains(url.absoluteString.lowercased())
    }

    static func isPermittedWebFetchRedirect(from originalURL: URL, to redirectURL: URL) -> Bool {
        guard originalURL.scheme == redirectURL.scheme,
              originalURL.port == redirectURL.port,
              redirectURL.user == nil,
              redirectURL.password == nil else {
            return false
        }
        let originalHost = (originalURL.host ?? "").removingWWWPrefix
        let redirectHost = (redirectURL.host ?? "").removingWWWPrefix
        return !originalHost.isEmpty && originalHost == redirectHost
    }

    static func isPreapprovedWebFetchURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return [
            "developer.apple.com",
            "docs.swift.org",
            "doc.rust-lang.org",
            "docs.python.org",
            "developer.mozilla.org",
            "github.com",
            "modelcontextprotocol.io",
            "platform.claude.com",
            "react.dev",
            "go.dev",
            "pkg.go.dev"
        ].contains(host)
    }
}

private extension String {
    var removingWWWPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}
