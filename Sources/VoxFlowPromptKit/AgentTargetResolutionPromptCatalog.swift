import Foundation

/// Catalog for Agent Dispatch target-resolution prompts.
///
/// This prompt chooses one existing task agent for a dictated instruction. It
/// must not create agents or send messages by itself.
public enum AgentTargetResolutionPromptCatalog {
    public static let system = PromptTemplate(
        kind: .agentTargetResolution,
        version: .v1_0_0,
        body: """
        You only reroute the dictated instruction to one target task agent from candidate_agents. Do not send messages or create new task agents.
        Return exactly one line of JSON: {"target_agent_id":"candidate ID","message":"original instruction content","confidence":0.0}.
        When uncertain, confidence must be lower than 0.60. target_agent_id must come from the candidate list.
        """
    )
}
