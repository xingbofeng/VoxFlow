import CoreAudio
import Foundation

@MainActor
final class SystemOutputMuter {
    private enum SavedState {
        case mute(device: AudioObjectID, value: UInt32)
        case volume(device: AudioObjectID, value: Float32)
    }

    private var savedState: SavedState?

    func setMuted(_ muted: Bool) {
        if muted {
            muteCurrentOutput()
        } else {
            restoreCurrentOutput()
        }
    }

    private func muteCurrentOutput() {
        guard savedState == nil, let device = defaultOutputDevice() else { return }

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
                    return
                }
            }
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &volumeAddress) else { return }
        var current: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &current) == noErr else {
            return
        }
        var silent: Float32 = 0
        if AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, size, &silent) == noErr {
            savedState = .volume(device: device, value: current)
        }
    }

    private func restoreCurrentOutput() {
        guard let savedState else { return }
        self.savedState = nil

        switch savedState {
        case let .mute(device, value):
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var restored = value
            let size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &restored)
        case let .volume(device, value):
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var restored = value
            let size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &restored)
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
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
