import Foundation

/// Catalog for the settings-page batch application classification prompt.
///
/// v1.0.0 preserves the exact wording previously inlined in
/// `LLMBatchApplicationClassifier`. The template exposes a `{{styleList}}`
/// placeholder for the rendered candidate style list. Migration MUST NOT
/// change behavior.
public enum BatchStyleClassificationPromptCatalog {
    public static let system = PromptTemplate(
        kind: .batchStyleClassification,
        version: .v1_0_0,
        body: """
        You are an application classification assistant. For each app, choose the most suitable style from the candidates using the app name, bundle ID, system category, and search clues.
        If your model or service supports web search, online search, or browser search tools, first search the table's Search Query and verify the app's real purpose before classifying it.
        If search is unavailable, classify cautiously from the app name, bundle ID, and known facts. Omit the app when uncertain.
        If an app is mainly a player, viewer, system settings app, hardware utility, or another tool without a real text-entry workflow, omit it instead of forcing a style.
        Do not classify unknown apps as the default style. Do not guess for coverage.
        Return a JSON object whose keys are app bundle IDs and whose values are style IDs.
        Use only these candidate style IDs:
        {{styleList}}

        Classification guide:
        - Chat, instant messaging, and community messaging: prefer builtin.chat.
        - IDEs, code editors, developer tools, terminals, API/database/proxy debugging tools: prefer builtin.coding.
        - Email clients or apps mainly used for writing email: prefer builtin.email.
        - Office documents, plans, long-form writing, presentations, and spreadsheets: prefer builtin.formal.
        - Browsers, launchers, daily utilities, and general consumer apps: prefer builtin.casual.
        - Use builtin.energetic only for apps that clearly need an upbeat motivational tone, such as team motivation, sports, or event operations.

        Output JSON only. Do not explain.
        Example format: {"com.example.app": "builtin.chat"}
        """
    )
}
