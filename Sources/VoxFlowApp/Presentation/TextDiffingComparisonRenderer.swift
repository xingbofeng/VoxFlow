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
        // Success / danger washes from the CDS semantic ramp instead of the
        // previous saturated pastel pair, which clashed with the warm canvas.
        let style = TextDiffStyle(
            insertedBackground: CDS.Semantic.successNSColor.withAlphaComponent(0.16),
            removedBackground: CDS.Semantic.dangerNSColor.withAlphaComponent(0.14)
        )
        return TextDiffer.diff(
            source,
            and: processed,
            style: style,
            options: [.tokenizeByCharacter, .strikethroughRemovedText]
        ).attributedString
    }
}
