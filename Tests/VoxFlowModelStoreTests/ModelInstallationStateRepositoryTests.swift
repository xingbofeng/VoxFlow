import XCTest
import VoxFlowModelStore

final class ModelInstallationStateRepositoryTests: XCTestCase {
    func testRepositoryPersistsLifecycleStateByInstallKey() throws {
        let fileURL = temporaryStateFileURL()
        let key = ModelInstallKey(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b-coreml-int8"),
            version: "2026.06.17"
        )
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: "/tmp/qwen3", isDirectory: true)
        )
        let repository = FileModelInstallationStateRepository(fileURL: fileURL)

        XCTAssertEqual(try repository.state(for: key), .notInstalled)

        try repository.save(.verifying, for: key)
        XCTAssertEqual(try repository.state(for: key), .verifying)

        try repository.save(.ready(installation), for: key)
        let reloaded = FileModelInstallationStateRepository(fileURL: fileURL)
        XCTAssertEqual(try reloaded.state(for: key), .ready(installation))
    }

    func testRepositoryRemovesOneInstallStateWithoutAffectingOthers() throws {
        let fileURL = temporaryStateFileURL()
        let first = ModelInstallKey(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b-coreml-int8"),
            version: "2026.06.17"
        )
        let second = ModelInstallKey(
            modelID: ModelID(rawValue: "whisper-turbo"),
            version: "2026.06.17"
        )
        let repository = FileModelInstallationStateRepository(fileURL: fileURL)

        try repository.save(.verifying, for: first)
        try repository.save(.warmingUp, for: second)
        try repository.removeState(for: first)

        XCTAssertEqual(try repository.state(for: first), .notInstalled)
        XCTAssertEqual(try repository.state(for: second), .warmingUp)
    }

    private func temporaryStateFileURL() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root.appendingPathComponent("installation-states.json")
    }
}
