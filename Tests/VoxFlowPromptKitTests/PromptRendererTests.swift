import XCTest
@testable import VoxFlowPromptKit

final class PromptRendererTests: XCTestCase {
    private let renderer = PromptRenderer()

    func testSubstitutesPlaceholders() {
        let template = PromptTemplate(
            kind: .styleRouter,
            version: .v1_0_0,
            body: "Hello {{name}}, you are {{role}}."
        )
        let result = renderer.render(
            template,
            context: PromptRenderContext.make(("name", "Vox"), ("role", "router"))
        )
        XCTAssertEqual(result.renderedText, "Hello Vox, you are router.")
    }

    func testToleratesWhitespaceInsideBraces() {
        let template = PromptTemplate(
            kind: .styleRouter,
            version: .v1_0_0,
            body: "Value: {{ name }}"
        )
        let result = renderer.render(
            template,
            context: PromptRenderContext.make(("name", "ok"))
        )
        XCTAssertEqual(result.renderedText, "Value: ok")
    }

    func testLeavesUnknownPlaceholdersUntouched() {
        let template = PromptTemplate(
            kind: .styleRouter,
            version: .v1_0_0,
            body: "Hello {{missing}} world"
        )
        let result = renderer.render(template)
        XCTAssertEqual(result.renderedText, "Hello {{missing}} world")
    }

    func testHashIsStableSHA256Hex() {
        let template = PromptTemplate(
            kind: .voiceCorrection,
            version: .v1_0_0,
            body: "fixed body"
        )
        let a = renderer.render(template)
        let b = renderer.render(template)
        XCTAssertEqual(a.renderedHash, b.renderedHash)
        XCTAssertEqual(a.renderedHash.count, 64)
        let regex = try? NSRegularExpression(pattern: "^[0-9a-f]{64}$")
        let range = NSRange(a.renderedHash.startIndex..<a.renderedHash.endIndex, in: a.renderedHash)
        XCTAssertNotNil(regex?.firstMatch(in: a.renderedHash, range: range))
    }

    func testHashChangesWhenContentChanges() {
        let t1 = PromptTemplate(kind: .voiceCorrection, version: .v1_0_0, body: "body A")
        let t2 = PromptTemplate(kind: .voiceCorrection, version: .v1_0_0, body: "body B")
        XCTAssertNotEqual(
            renderer.render(t1).renderedHash,
            renderer.render(t2).renderedHash
        )
    }

    func testRenderResultCarriesTemplateMetadata() {
        let template = PromptTemplate(
            kind: .agentCompose,
            version: PromptVersion(major: 1, minor: 2, patch: 3),
            body: "x"
        )
        let result = renderer.render(template)
        XCTAssertEqual(result.kind, .agentCompose)
        XCTAssertEqual(result.version, PromptVersion(major: 1, minor: 2, patch: 3))
    }
}
