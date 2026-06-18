import Foundation

struct ASRSmokeManifest: Decodable {
    let version: Int
    let samples: [ASRSmokeSample]

    static func loadDefault(
        fileManager: FileManager = .default,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> ASRSmokeManifest {
        let url = currentDirectory
            .appendingPathComponent("TestResources")
            .appendingPathComponent("ASRSmoke")
            .appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ASRSmokeManifest.self, from: data)
    }
}

struct ASRSmokeSample: Decodable, Equatable, Sendable {
    let id: String
    let language: String
    let audioPath: String
    let transcriptPath: String?
    let expectsSpeech: Bool
    let allowsEmptyFinal: Bool
    let requiresPartialWhenStreaming: Bool
    let maxFinalLatencyMilliseconds: Int
}
