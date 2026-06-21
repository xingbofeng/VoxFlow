import Foundation

public struct BoundaryClassifier: Sendable {
    public init() {}

    public func isBoundaryMatch(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        guard range.lowerBound < range.upperBound else {
            return false
        }

        let first = text[range].first
        let last = text[range].last

        if let first, Self.isWordConstituent(first), range.lowerBound > text.startIndex {
            let previousIndex = text.index(before: range.lowerBound)
            if Self.isWordConstituent(text[previousIndex]) {
                return false
            }
        }

        if let last, Self.isWordConstituent(last), range.upperBound < text.endIndex {
            if Self.isWordConstituent(text[range.upperBound]) {
                return false
            }
        }

        return true
    }

    private static func isWordConstituent(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }
}
