import Foundation

public enum TextInputMode: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case fastPaste
    case simulatedTyping
}
