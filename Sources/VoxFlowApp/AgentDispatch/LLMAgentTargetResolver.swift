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
        AppLogger.dictation.debug("LLMAgentTargetResolver resolve utteranceLen=\(utterance.count) candidates=\(candidates.count)")
        guard await isEnabled(), !candidates.isEmpty else {
            AppLogger.dictation.debug("LLMAgentTargetResolver skipped: disabled or empty candidates")
            return nil
        }
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
                You only reroute the dictated instruction to one target task agent from candidate_agents. Do not send messages or create new task agents.
                Return exactly one line of JSON: {"target_agent_id":"candidate ID","message":"original instruction content","confidence":0.0}.
                When uncertain, confidence must be lower than 0.60. target_agent_id must come from the candidate list.
                """,
                model: nil,
                temperature: 0,
                purpose: .directTask
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
            AppLogger.dictation.warning("LLMAgentTargetResolver parse/validate failed utteranceLen=\(utterance.count)")
            return nil
        }
        AppLogger.dictation.debug(
            "LLMAgentTargetResolver resolved target=\(decoded.targetAgentID) confidence=\(decoded.confidence) messageLen=\(decoded.message.count)"
        )
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
