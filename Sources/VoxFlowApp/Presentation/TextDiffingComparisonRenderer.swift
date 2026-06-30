import AppKit
import Foundation
import TextDiffing

/// TextDiffing-backed attributed renderer for inline comparison mode.
///
/// `TextComparisonPresentation` still owns the lightweight segment model used
/// by tests, similarity, and accessibility. Rendering goes through TextDiffing
/// so the UI uses the open-source diff package while keeping our callers behind
/// an internal boundary.
struct TextDiffingComparisonRenderer: Sendable {
    let isTextDiffingBacked = true

    func attributedString(source: String, processed: String) -> AttributedString {
        let style = TextDiffStyle(
            insertedBackground: NSColor(red: 0.878, green: 0.965, blue: 0.878, alpha: 1),
            removedBackground: NSColor(red: 0.985, green: 0.890, blue: 0.890, alpha: 1)
        )
        return TextDiffer.diff(
            source,
            and: processed,
            style: style,
            options: [.tokenizeByCharacter, .strikethroughRemovedText]
        ).attributedString
    }
}
