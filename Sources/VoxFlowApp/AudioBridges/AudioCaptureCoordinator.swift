import Foundation

enum AudioCaptureKind: String, Equatable, Sendable {
    case dictation
    case agentCompose
    case notes
}

struct AudioCaptureLease: Equatable, Sendable {
    let id: UUID
    let kind: AudioCaptureKind
}

enum AudioCaptureCoordinatorError: LocalizedError, Equatable {
    case busy(active: AudioCaptureKind, requested: AudioCaptureKind)

    var errorDescription: String? {
        switch self {
        case .busy(let active, let requested):
            return "音频录制已被 \(active.localizedName) 占用，无法启动 \(requested.localizedName)。"
        }
    }
}

@MainActor
protocol AudioCaptureCoordinating: AnyObject {
    func begin(kind: AudioCaptureKind) throws -> AudioCaptureLease
    func end(_ lease: AudioCaptureLease)
}

@MainActor
final class AudioCaptureCoordinator: AudioCaptureCoordinating {
    private var activeLease: AudioCaptureLease?

    func begin(kind: AudioCaptureKind) throws -> AudioCaptureLease {
        if let activeLease {
            throw AudioCaptureCoordinatorError.busy(active: activeLease.kind, requested: kind)
        }
        let lease = AudioCaptureLease(id: UUID(), kind: kind)
        activeLease = lease
        return lease
    }

    func end(_ lease: AudioCaptureLease) {
        guard activeLease == lease else { return }
        activeLease = nil
    }
}

private extension AudioCaptureKind {
    var localizedName: String {
        switch self {
        case .dictation:
            return "听写"
        case .agentCompose:
            return "帮我说"
        case .notes:
            return "笔记录音"
        }
    }
}
