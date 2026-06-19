import FluidAudio
import Foundation

public enum SenseVoiceModel {
    public static let modelID = "sensevoice-small-coreml-fp16"
    public static let version = Repo.senseVoiceSmall.folderName
    public static let precision: SenseVoiceEncoderPrecision = .fp16

    public static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.senseVoiceSmall.folderName, isDirectory: true)
    }

    public static func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        SenseVoiceModels.modelsExist(at: directory, precision: precision)
    }
}
