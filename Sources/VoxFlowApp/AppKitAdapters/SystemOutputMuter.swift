import CoreAudio
import Foundation

@MainActor
final class SystemOutputMuter {
    private let logger = AppLogger.audio

    private enum SavedState {
        case mute(device: AudioObjectID, value: UInt32)
        case volume(device: AudioObjectID, value: Float32)
    }

    private var savedState: SavedState?

    func setMuted(_ muted: Bool) {
        logger.debug("SystemOutputMuter setMuted requested: muted=\(muted) hasSavedState=\(savedState != nil)")
        if muted {
            muteCurrentOutput()
        } else {
            restoreCurrentOutput()
        }
    }

    private func muteCurrentOutput() {
        guard savedState == nil else {
            logger.debug("SystemOutputMuter mute skipped: already muted state cached")
            return
        }
        guard let device = defaultOutputDevice() else {
            logger.warning("SystemOutputMuter mute skipped: no default output device")
            return
        }

        logger.debug("SystemOutputMuter muting device=\(device)")

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &muteAddress) {
            var current: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &current) == noErr {
                var muted: UInt32 = 1
                if AudioObjectSetPropertyData(device, &muteAddress, 0, nil, size, &muted) == noErr {
                    savedState = .mute(device: device, value: current)
                    logger.debug("SystemOutputMuter muted via device mute current=\(current)")
                    return
                }
                logger.warning("SystemOutputMuter mute setProperty failed for mute")
            }
            logger.debug("SystemOutputMuter mute getProperty returned non-zero current unavailable")
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &volumeAddress) else {
            logger.warning("SystemOutputMuter fallback skipped: device volume property unavailable")
            return
        }
        var current: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &current) == noErr else {
            logger.warning("SystemOutputMuter fallback failed: get volume property failed")
            return
        }
        var silent: Float32 = 0
        if AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, size, &silent) == noErr {
            savedState = .volume(device: device, value: current)
            logger.debug("SystemOutputMuter muted via volume fallback current=\(current)")
            return
        }
        logger.warning("SystemOutputMuter fallback failed: set volume to silent failed")
    }

    private func restoreCurrentOutput() {
        guard let savedState else {
            logger.debug("SystemOutputMuter restore skipped: no saved state")
            return
        }
        self.savedState = nil
        logger.debug("SystemOutputMuter restoring saved state")

        switch savedState {
        case let .mute(device, value):
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var restored = value
            let size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &restored)
            if status == noErr {
                logger.debug("SystemOutputMuter restore mute success device=\(device) value=\(value)")
            } else {
                logger.warning("SystemOutputMuter restore mute failed status=\(status)")
            }
        case let .volume(device, value):
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var restored = value
            let size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &restored)
            if status == noErr {
                logger.debug("SystemOutputMuter restore volume success device=\(device) value=\(value)")
            } else {
                logger.warning("SystemOutputMuter restore volume failed status=\(status)")
            }
        }
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        if status != noErr {
            logger.debug("SystemOutputMuter get default output device failed status=\(status)")
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
