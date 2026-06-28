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
            return String(
                format: L10n.localize("audio.capture.error.busy", comment: "Audio capture busy error message"),
                active.localizedName,
                requested.localizedName
            )
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
            AppLogger.audio.warning("音频采集启动失败：已有活动租约 active=\(activeLease.kind.rawValue) request=\(kind.rawValue)")
            throw AudioCaptureCoordinatorError.busy(active: activeLease.kind, requested: kind)
        }
        let lease = AudioCaptureLease(id: UUID(), kind: kind)
        activeLease = lease
        AppLogger.audio.debug("音频采集租约建立：\(lease.kind.rawValue), id=\(lease.id.uuidString)")
        return lease
    }

    func end(_ lease: AudioCaptureLease) {
        guard activeLease == lease else {
            AppLogger.audio.debug("音频采集租约忽略结束：非当前租约, id=\(lease.id.uuidString)")
            return
        }
        activeLease = nil
        AppLogger.audio.debug("音频采集租约结束：\(lease.kind.rawValue), id=\(lease.id.uuidString)")
    }
}

    private extension AudioCaptureKind {
    var localizedName: String {
        switch self {
        case .dictation:
            return L10n.localize("audio.capture.kind.dictation", comment: "Audio capture kind name: dictation mode")
        case .agentCompose:
            return L10n.localize("audio.capture.kind.agent_compose", comment: "Audio capture kind name: agent compose mode")
        case .notes:
            return L10n.localize("audio.capture.kind.notes", comment: "Audio capture kind name: notes recording mode")
        }
    }
}
