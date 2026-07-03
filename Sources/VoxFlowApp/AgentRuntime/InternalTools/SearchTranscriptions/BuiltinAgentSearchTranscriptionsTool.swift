import Foundation

extension BuiltinAgentToolHost {
    func searchTranscriptions(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let query = requiredString("query", in: call) else {
            return .failure(toolName: call.name, code: "missing_query")
        }
        guard let historyRepository = environment.historyRepository else {
            return .failure(toolName: call.name, code: "transcription_search_unavailable")
        }
        let limit = min(max(optionalInt("limit", in: call) ?? 5, 1), 20)
        do {
            let entries = try historyRepository.search(query, limit: limit)
            return .success(
                toolName: call.name,
                result: [
                    "entries": .array(entries.map { entry in
                        .object([
                            "id": .string(entry.id),
                            "rawText": .string(entry.rawText),
                            "finalText": .string(entry.finalText),
                            "createdAt": .string(ISO8601DateFormatter().string(from: entry.createdAt)),
                            "targetAppName": entry.targetAppName.map(BuiltinAgentJSONValue.string) ?? .null
                        ])
                    })
                ]
            )
        } catch {
            return .failure(toolName: call.name, code: "transcription_search_failed", message: error.localizedDescription)
        }
    }
}
