import Foundation

final class LLMAgentTargetResolver: AgentTargetModelResolving, @unchecked Sendable {
    private let refiner: any PromptAwareTextRefining
    private let isEnabled: @Sendable () async -> Bool

    init(
        refiner: any PromptAwareTextRefining,
        isEnabled: @escaping @Sendable () async -> Bool
    ) {
        self.refiner = refiner
        self.isEnabled = isEnabled
    }

    func resolve(
        utterance: String,
        candidates: [AgentSessionCard]
    ) async throws -> AgentModelResolution? {
        guard await isEnabled(), !candidates.isEmpty else { return nil }
        let candidatePayload = candidates.map { candidate in
            [
                "agent_id": candidate.agentID,
                "display_name": candidate.displayName,
                "cli": candidate.cli,
                "repo_name": candidate.repoName ?? "",
                "branch": candidate.branch ?? "",
                "summary": candidate.currentSelfSummary?.summary ?? "",
            ]
        }
        let inputData = try JSONSerialization.data(
            withJSONObject: ["utterance": utterance, "candidate_agents": candidatePayload],
            options: [.sortedKeys]
        )
        let input = String(data: inputData, encoding: .utf8) ?? "{}"
        let response = try await refiner.refine(
            TextRefinementRequest(
                text: input,
                systemPrompt: """
                你只负责从 candidate_agents 中重排语音指令的目标队员，不得发送消息或创造新队员。
                只返回单行 JSON：{"target_agent_id":"候选ID","message":"原指令内容","confidence":0.0}。
                不确定时 confidence 必须低于 0.60；target_agent_id 必须来自候选列表。
                """,
                model: nil,
                temperature: 0
            )
        )
        let json = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              candidates.contains(where: { $0.agentID == decoded.targetAgentID }),
              (0...1).contains(decoded.confidence) else {
            return nil
        }
        return AgentModelResolution(
            agentID: decoded.targetAgentID,
            message: decoded.message,
            confidence: decoded.confidence
        )
    }

    private struct Response: Decodable {
        let targetAgentID: String
        let message: String
        let confidence: Double

        private enum CodingKeys: String, CodingKey {
            case targetAgentID = "target_agent_id"
            case message, confidence
        }
    }
}
