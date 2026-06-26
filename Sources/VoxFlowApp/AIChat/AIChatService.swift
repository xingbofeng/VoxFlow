import Foundation

/// 问 AI 聊天服务协议。复用用户已配置的 LLM provider 与凭据，
/// 但不注入纠错 system prompt，仅承载多轮 user/assistant 消息。
protocol AIChatServicing: AnyObject, Sendable {
    /// 是否已配置可用 LLM provider 且存在 API Key。
    var isConfigured: Bool { get }

    /// 以多轮消息发起流式请求，yield 累计文本快照。
    func streamResponse(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error>
}
