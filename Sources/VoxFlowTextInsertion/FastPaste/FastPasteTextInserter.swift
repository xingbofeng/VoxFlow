import AppKit
import Carbon

public enum InputSourceClassifier {
    private static let knownCJKPrefixes = [
        "com.apple.inputmethod.SCIM",
        "com.apple.inputmethod.TCIM",
        "com.apple.inputmethod.Kotoeri",
        "com.apple.inputmethod.Korean",
    ]

    public static func isCJK(sourceID: String, languages: [String]) -> Bool {
        if knownCJKPrefixes.contains(where: sourceID.hasPrefix) {
            return true
        }

        return languages.contains { language in
            let normalized = language.lowercased()
            return normalized == "zh"
                || normalized.hasPrefix("zh-")
                || normalized == "ja"
                || normalized.hasPrefix("ja-")
                || normalized == "ko"
                || normalized.hasPrefix("ko-")
        }
    }
}

/// Handles fast paste insertion into the currently focused input field.
/// Saves/restores clipboard, detects CJK input methods, switches to ASCII if needed,
/// and simulates Cmd+V paste.
@MainActor
public final class FastPasteTextInserter: TextInserting {
    private let shouldRestoreClipboard: @MainActor () -> Bool
    private let allowsSystemInteraction: @MainActor () -> Bool

    public init(
        shouldRestoreClipboard: @escaping @MainActor () -> Bool = { true },
        allowsSystemInteraction: @escaping @MainActor () -> Bool = {
            !TextInsertionRuntimeEnvironment.isRunningUnderXCTest()
        }
    ) {
        self.shouldRestoreClipboard = shouldRestoreClipboard
        self.allowsSystemInteraction = allowsSystemInteraction
    }

    public func insert(_ text: String) async -> TextInsertionResult {
        guard !text.isEmpty else { return .success }
        guard allowsSystemInteraction() else {
            return .unavailable(reason: "Fast paste system interaction is disabled during tests")
        }

        guard AXIsProcessTrusted() else {
            return .permissionDenied
        }

        let savedInputSource = getCurrentInputSource()
        let wasCJK = isCJKInputSource(savedInputSource)

        let switchedInputSource = wasCJK && switchToASCIIInputSource()
        if switchedInputSource {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let pasteboard = NSPasteboard.general
        let pasteboardTransaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: text
        )

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            if switchedInputSource, let savedSource = savedInputSource {
                restoreInputSource(savedSource)
            }
            if shouldRestoreClipboard() {
                pasteboardTransaction.restoreOriginalIfUnchanged(on: pasteboard)
            }
            return .eventCreationFailed
        }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)

        _ = await PasteCompletionWaiter().waitForPasteWindow(
            on: pasteboard,
            transaction: pasteboardTransaction
        )

        if switchedInputSource, let savedSource = savedInputSource {
            restoreInputSource(savedSource)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if shouldRestoreClipboard() {
            pasteboardTransaction.restoreOriginalIfUnchanged(on: pasteboard)
        }

        return .success
    }

    private func getCurrentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func isCJKInputSource(_ source: TISInputSource?) -> Bool {
        guard let source else { return false }

        guard let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return false
        }

        let id = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String

        var languages: [String] = []
        if let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let value = Unmanaged<CFArray>.fromOpaque(property).takeUnretainedValue()
            languages = value as? [String] ?? []
        }

        return InputSourceClassifier.isCJK(sourceID: id, languages: languages)
    }

    private func switchToASCIIInputSource() -> Bool {
        guard let asciiSource = findASCIIInputSource() else {
            return false
        }
        return TISSelectInputSource(asciiSource) == noErr
    }

    private func findASCIIInputSource() -> TISInputSource? {
        let asciiIDs = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.British",
        ]

        for id in asciiIDs {
            if let source = findInputSource(byID: id) {
                return source
            }
        }

        return nil
    }

    private func findInputSource(byID id: String) -> TISInputSource? {
        let dict = [
            kTISPropertyInputSourceID as String: id
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(dict, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else {
            return nil
        }

        guard let categoryProperty = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory),
              let category = Unmanaged<CFString>.fromOpaque(categoryProperty).takeUnretainedValue() as String?,
              category == kTISCategoryKeyboardInputSource as String else {
            return nil
        }

        return source
    }

    private func restoreInputSource(_ source: TISInputSource) {
        TISSelectInputSource(source)
    }
}
