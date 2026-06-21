import Foundation

struct GlossaryTerm: Equatable {
    let id: String
    let term: String
    let aliases: [String]
    let category: String
    let enabled: Bool
    let priority: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}
