import XCTest

final class ASRSmokeManifestTests: XCTestCase {
    func testManifestDefinesMinimalSmokeCorpus() throws {
        let manifest = try ASRSmokeManifest.loadDefault()

        XCTAssertEqual(manifest.samples.map(\.id), [
            "zh_short",
            "en_short",
            "zh_long",
            "silence",
        ])
        XCTAssertEqual(manifest.samples.filter(\.expectsSpeech).count, 3)
        XCTAssertTrue(manifest.samples.first { $0.id == "silence" }?.allowsEmptyFinal == true)
        XCTAssertEqual(
            manifest.samples.filter(\.requiresPartialWhenStreaming).map(\.id),
            ["zh_short", "zh_long"]
        )
    }

    func testManifestAudioFilesDecodeToAudioFrames() throws {
        let manifest = try ASRSmokeManifest.loadDefault()

        for sample in manifest.samples {
            let frames = try ASRSmokeAudio.loadFrames(for: sample)

            XCTAssertFalse(frames.isEmpty, "Expected audio frames for \(sample.id)")
            XCTAssertEqual(frames.first?.sampleRate, 16_000)
        }
    }
}
