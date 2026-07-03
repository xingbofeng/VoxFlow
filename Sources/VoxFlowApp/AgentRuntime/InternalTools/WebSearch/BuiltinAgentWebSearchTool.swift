import Foundation

private struct BuiltinAgentWebSearchHit: Equatable {
    let title: String
    let url: String
    let snippet: String?

    var domain: String? {
        URL(string: url)?.host?.removingWWWPrefixForSearch.lowercased()
    }

    var json: BuiltinAgentJSONValue {
        var object: [String: BuiltinAgentJSONValue] = [
            "title": .string(title),
            "url": .string(url)
        ]
        if let snippet {
            object["snippet"] = .string(snippet)
        }
        return .object(object)
    }
}

extension BuiltinAgentToolHost {
    func webSearch(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let query = requiredString("query", in: call), query.count >= 2 else {
            return .failure(toolName: call.name, code: "missing_query")
        }
        let allowedDomains = Set(stringArray("allowed_domains", in: call).map(normalizedSearchDomain))
        let blockedDomains = Set(stringArray("blocked_domains", in: call).map(normalizedSearchDomain))
        guard allowedDomains.isEmpty || blockedDomains.isEmpty else {
            return .failure(toolName: call.name, code: "conflicting_domain_filters")
        }

        let start = Date()
        let limit = min(max(optionalInt("num_results", in: call) ?? 8, 1), 20)
        guard let url = webSearchURL(query: query) else {
            return .failure(toolName: call.name, code: "invalid_query")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VoxFlow-Agent/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await environment.httpClient(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(toolName: call.name, code: "invalid_response")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .failure(toolName: call.name, code: "web_search_http_error", message: "HTTP \(httpResponse.statusCode)")
            }
            let hits = try parseWebSearchHits(data)
                .filter { hit in
                    guard let domain = hit.domain else { return false }
                    if !allowedDomains.isEmpty {
                        return allowedDomains.contains(domain)
                    }
                    return !blockedDomains.contains(domain)
                }
                .prefix(limit)
            let content = hits.map(\.json)
            let results: [BuiltinAgentJSONValue]
            if content.isEmpty {
                results = [.string("No search results found.")]
            } else {
                results = [
                    .object([
                        "tool_use_id": .string(call.id),
                        "content": .array(Array(content))
                    ])
                ]
            }
            return .success(
                toolName: call.name,
                result: [
                    "query": .string(query),
                    "results": .array(results),
                    "durationSeconds": .int(Int(Date().timeIntervalSince(start)))
                ]
            )
        } catch let error as BuiltinAgentToolHostError {
            return .failure(toolName: call.name, code: error.code, message: error.message)
        } catch {
            return .failure(toolName: call.name, code: "web_search_failed", message: error.localizedDescription)
        }
    }

    private func webSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        return components?.url
    }

    private func parseWebSearchHits(_ data: Data) throws -> [BuiltinAgentWebSearchHit] {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw BuiltinAgentToolHostError(code: "invalid_search_response", message: "Search response must be a JSON object.")
        }
        var hits: [BuiltinAgentWebSearchHit] = []
        if let results = object["results"] as? [[String: Any]] {
            hits.append(contentsOf: results.compactMap(searchHit))
        }
        if let relatedTopics = object["RelatedTopics"] as? [[String: Any]] {
            hits.append(contentsOf: flattenDuckDuckGoTopics(relatedTopics).compactMap(searchHit))
        }
        return hits
    }

    private func flattenDuckDuckGoTopics(_ topics: [[String: Any]]) -> [[String: Any]] {
        topics.flatMap { topic -> [[String: Any]] in
            if let nested = topic["Topics"] as? [[String: Any]] {
                return flattenDuckDuckGoTopics(nested)
            }
            return [topic]
        }
    }

    private func searchHit(_ object: [String: Any]) -> BuiltinAgentWebSearchHit? {
        if let title = object["title"] as? String,
           let url = object["url"] as? String {
            return BuiltinAgentWebSearchHit(
                title: title,
                url: url,
                snippet: object["snippet"] as? String
            )
        }
        guard let firstURL = object["FirstURL"] as? String else { return nil }
        let text = (object["Text"] as? String) ?? firstURL
        let title = text.components(separatedBy: " - ").first ?? text
        return BuiltinAgentWebSearchHit(title: title, url: firstURL, snippet: text)
    }

    private func normalizedSearchDomain(_ domain: String) -> String {
        domain.lowercased().removingWWWPrefixForSearch
    }
}

private extension String {
    var removingWWWPrefixForSearch: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}
