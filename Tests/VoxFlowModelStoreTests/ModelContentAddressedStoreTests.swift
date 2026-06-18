import XCTest
import VoxFlowModelStore

final class ModelContentAddressedStoreTests: XCTestCase {
    func testStoresBlobUnderSHA256Path() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("source.bin")
        try Data("hello".utf8).write(to: source)
        let digest = SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

        let blobURL = try ModelContentAddressedStore(root: root).storeBlob(
            from: source,
            expectedSHA256: digest
        )

        XCTAssertEqual(blobURL.path, root.appendingPathComponent("blobs").appendingPathComponent(digest.rawValue).path)
        XCTAssertEqual(try Data(contentsOf: blobURL), Data("hello".utf8))
    }

    func testProviderInstallDirectoriesReferenceSharedBlobWithoutDuplicatingData() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("tokenizer.json")
        try Data("hello".utf8).write(to: source)
        let digest = SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        let store = ModelContentAddressedStore(root: root)
        _ = try store.storeBlob(from: source, expectedSHA256: digest)

        let qwenTokenizer = root.appendingPathComponent("providers/qwen3/tokenizer.json")
        let whisperTokenizer = root.appendingPathComponent("providers/whisper/tokenizer.json")
        try store.linkBlob(digest, to: qwenTokenizer)
        try store.linkBlob(digest, to: whisperTokenizer)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("blobs").path), [digest.rawValue])
        XCTAssertEqual(try store.referenceCount(for: digest), 3)
        XCTAssertEqual(try Data(contentsOf: qwenTokenizer), Data("hello".utf8))
        XCTAssertEqual(try Data(contentsOf: whisperTokenizer), Data("hello".utf8))
    }

    func testDeleteReferenceRemovesBlobOnlyAfterLastProviderReference() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("vad.bin")
        try Data("hello".utf8).write(to: source)
        let digest = SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        let store = ModelContentAddressedStore(root: root)
        let blobURL = try store.storeBlob(from: source, expectedSHA256: digest)

        let paraformerVAD = root.appendingPathComponent("providers/paraformer/vad.bin")
        let senseVoiceVAD = root.appendingPathComponent("providers/sensevoice/vad.bin")
        try store.linkBlob(digest, to: paraformerVAD)
        try store.linkBlob(digest, to: senseVoiceVAD)

        try store.deleteReference(at: paraformerVAD)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobURL.path))
        XCTAssertEqual(try store.referenceCount(for: digest), 2)

        try store.deleteReference(at: senseVoiceVAD)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL.path))
    }

    func testRejectsBlobWhenSHA256DoesNotMatch() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("source.bin")
        try Data("wrong".utf8).write(to: source)

        XCTAssertThrowsError(
            try ModelContentAddressedStore(root: root).storeBlob(
                from: source,
                expectedSHA256: SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
