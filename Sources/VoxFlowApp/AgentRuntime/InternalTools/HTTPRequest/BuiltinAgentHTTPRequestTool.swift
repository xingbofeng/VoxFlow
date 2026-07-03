import Foundation

extension BuiltinAgentToolHost {
    func httpRequest(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let urlString = requiredString("url", in: call),
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else {
            return .failure(toolName: call.name, code: "invalid_https_url")
        }
        guard Self.userExplicitlyMentionedURL(url, instruction: environment.userInstruction) else {
            return .failure(toolName: call.name, code: "missing_explicit_user_intent")
        }
        let method = (requiredString("method", in: call) ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method) else {
            return .failure(toolName: call.name, code: "unsupported_http_method")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body = call.arguments["body"]?.stringValue {
            request.httpBody = Data(body.utf8)
        }
        if case let .object(headers)? = call.arguments["headers"] {
            for (key, value) in headers {
                if let headerValue = value.stringValue {
                    request.setValue(headerValue, forHTTPHeaderField: key)
                }
            }
        }
        do {
            let (data, response) = try await environment.httpClient(request)
            let httpResponse = response as? HTTPURLResponse
            let text = String(data: data, encoding: .utf8) ?? ""
            return .success(
                toolName: call.name,
                result: [
                    "statusCode": .int(httpResponse?.statusCode ?? 0),
                    "body": .string(text.truncated(limit: Self.maxHTTPBodyCharacters)),
                    "truncated": .bool(text.count > Self.maxHTTPBodyCharacters)
                ]
            )
        } catch {
            return .failure(toolName: call.name, code: "http_request_failed", message: error.localizedDescription)
        }
    }
}
