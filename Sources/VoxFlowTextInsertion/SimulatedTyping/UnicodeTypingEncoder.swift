public struct UnicodeTypingEncoder {
    public init() {}

    public func graphemeClusters(in text: String) -> [String] {
        text.map(String.init)
    }
}
