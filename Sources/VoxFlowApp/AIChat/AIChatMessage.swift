import Foundation

/// 问 AI 单条消息模型。
struct AIChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    enum Status: Equatable, Sendable {
        case complete
        case streaming
        case failed(String)
    }

    let id: UUID
    let role: Role
    var content: String
    var status: Status
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        status: Status = .complete,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.createdAt = createdAt
    }
}
