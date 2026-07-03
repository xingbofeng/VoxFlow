import Foundation
@preconcurrency import AVFoundation

struct PreparedFileTranscriptionAudio {
    let url: URL
    let cleanup: () -> Void
}

enum FileTranscriptionAudioAssetPreparer {
    static func prepare(_ sourceURL: URL) async throws -> PreparedFileTranscriptionAudio {
        if (try? AVAudioFile(forReading: sourceURL)) != nil {
            return PreparedFileTranscriptionAudio(url: sourceURL, cleanup: {})
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlow-file-transcription-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: sourceURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw FileTranscriptionError.unsupportedAudioContainer(sourceURL.lastPathComponent)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw FileTranscriptionError.unsupportedAudioContainer(sourceURL.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw FileTranscriptionError.unsupportedAudioContainer(sourceURL.lastPathComponent)
        }

        guard (try? AVAudioFile(forReading: outputURL)) != nil else {
            try? FileManager.default.removeItem(at: outputURL)
            throw FileTranscriptionError.unsupportedAudioContainer(sourceURL.lastPathComponent)
        }

        return PreparedFileTranscriptionAudio(url: outputURL) {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}
