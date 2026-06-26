import Foundation

/// 问 AI 会话 ViewModel。持有内存会话、流式状态、停止/失败处理。
@MainActor
final class AIChatSessionViewModel: ObservableObject {
    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var configurationError: String?
    @Published var inputText: String = ""

    private let service: any AIChatServicing
    private var streamTask: Task<Void, Never>?
    private var currentAssistantID: UUID?

    init(service: any AIChatServicing) {
        self.service = service
    }

    /// 发送一条用户消息并开始流式回复。
    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard service.isConfigured else {
            configurationError = "未配置 AI 模型"
            return
        }
        configurationError = nil

        let userMessage = AIChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        let history = messages

        let assistantMessage = AIChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(assistantMessage)
        currentAssistantID = assistantMessage.id
        isStreaming = true

        startStreaming(assistantID: assistantMessage.id, history: history)
    }

    /// 停止当前流式请求，保留已生成内容并标记为完成。
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        if let id = currentAssistantID {
            update(assistantID: id, status: .complete)
        }
        isStreaming = false
        currentAssistantID = nil
    }

    /// 重置会话（清空内存消息）。
    func reset() {
        stop()
        messages = []
        configurationError = nil
        inputText = ""
    }

    private func startStreaming(assistantID: UUID, history: [AIChatMessage]) {
        streamTask?.cancel()
        let service = self.service
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = service.streamResponse(messages: history)
                for try await accumulatedText in stream {
                    self.update(assistantID: assistantID, content: accumulatedText, status: .streaming)
                }
                self.update(assistantID: assistantID, status: .complete)
            } catch {
                self.update(assistantID: assistantID, status: .failed(error.localizedDescription))
            }
            self.isStreaming = false
            self.currentAssistantID = nil
        }
    }

    private func update(
        assistantID: UUID,
        content: String? = nil,
        status: AIChatMessage.Status
    ) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        if let content {
            messages[index].content = content
        }
        messages[index].status = status
    }
}
