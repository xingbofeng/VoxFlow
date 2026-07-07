// DictusKeyboard/Vendored/Controllers/Audio.swift
// Vendored from giellakbd-ios Keyboard/Controllers/Audio.swift
// Stripped: KeyboardSettings reference removed
// Note: AudioServicesPlaySystemSound respects the silent switch natively.
// Dictus has no key sound toggle yet -- sounds always play (matching current behavior).

import Foundation
import AVFoundation

@MainActor
public final class GiellaAudio {
    public static func playClickSound() {
        let clickSound: SystemSoundID = 1104
        play(systemSound: clickSound)
    }

    public static func playModifierSound() {
        let modifierSound: SystemSoundID = 1156
        play(systemSound: modifierSound)
    }

    public static func playDeleteSound() {
        let deleteSound: SystemSoundID = 1155
        play(systemSound: deleteSound)
    }

    private static func play(systemSound: SystemSoundID) {
        DispatchQueue.global().async {
            AudioServicesPlaySystemSound(systemSound)
        }
    }
}
