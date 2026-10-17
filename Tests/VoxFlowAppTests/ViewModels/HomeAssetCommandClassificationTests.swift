import XCTest
@testable import VoxFlowApp

/// Home history must distinguish voice-command tasks from plain dictation.
/// Before this, `command` tasks were labelled "Voice" and swallowed by the
/// dictation filter, while their detail page already said "Voice Command".
final class HomeAssetCommandClassificationTests: XCTestCase {
    private func makeItem(voiceKind: VoiceAssetKind?) throws -> HomeAssetItem {
        let asset = try AssetItem.makeText(
            id: "asset-\(voiceKind?.rawValue ?? "nil")",
            source: .dictation,
            title: "title",
            text: "text",
            contentHash: "hash-\(voiceKind?.rawValue ?? "nil")",
            captureReason: .dictationCompleted
        )
        return HomeAssetItem(asset: asset, voiceKind: voiceKind)
    }

    // MARK: - VoiceAssetKind

    func testVoiceAssetKindDecodesCommandRawValue() {
        XCTAssertEqual(VoiceAssetKind(rawValue: "command"), .command)
    }

    func testUnknownVoiceAssetKindStillFallsBackToDictation() {
        XCTAssertEqual(VoiceAssetKind(rawValue: "somethingElse"), .dictation)
        XCTAssertEqual(VoiceAssetKind(rawValue: nil), .dictation)
    }

    // MARK: - Source label

    func testCommandItemSourceTitleIsNotDictation() throws {
        let commandItem = try makeItem(voiceKind: .command)
        let dictationItem = try makeItem(voiceKind: .dictation)

        XCTAssertNotEqual(
            commandItem.sourceTitle,
            dictationItem.sourceTitle,
            "A voice-command task must not be labelled the same as plain dictation."
        )
    }

    // MARK: - Filters

    func testCommandItemIsNotSwallowedByDictationFilter() throws {
        let commandItem = try makeItem(voiceKind: .command)

        XCTAssertFalse(
            HomeAssetSourceFilter.dictation.matches(commandItem),
            "Voice-command tasks must not appear under the dictation filter."
        )
    }

    func testCommandItemMatchesCommandFilter() throws {
        let commandItem = try makeItem(voiceKind: .command)

        XCTAssertTrue(HomeAssetSourceFilter.command.matches(commandItem))
    }

    func testCommandFilterExcludesOtherVoiceKinds() throws {
        let filter = HomeAssetSourceFilter.command

        XCTAssertFalse(filter.matches(try makeItem(voiceKind: .dictation)))
        XCTAssertFalse(filter.matches(try makeItem(voiceKind: .agentCompose)))
        XCTAssertFalse(filter.matches(try makeItem(voiceKind: .agentDispatch)))
    }

    func testDictationFilterStillMatchesPlainDictation() throws {
        XCTAssertTrue(HomeAssetSourceFilter.dictation.matches(try makeItem(voiceKind: .dictation)))
    }

    func testCommandFilterUsesDerivedVoiceFiltering() {
        XCTAssertTrue(HomeAssetSourceFilter.command.requiresDerivedFiltering)
        XCTAssertEqual(HomeAssetSourceFilter.command.assetSources, [.dictation])
    }

    func testAllFilterStillShowsCommandItems() throws {
        XCTAssertTrue(HomeAssetSourceFilter.all.matches(try makeItem(voiceKind: .command)))
    }
}
