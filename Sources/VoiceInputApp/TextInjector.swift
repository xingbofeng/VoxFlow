import AppKit
import Carbon

enum InjectionResult: Equatable {
    case success
    case permissionDenied
    case eventCreationFailed
    case cancelled
}

struct PasteboardSnapshot {
    struct Item {
        let representations: [NSPasteboard.PasteboardType: Data]
    }

    let items: [Item]

    init(items: [NSPasteboardItem]) {
        self.items = items.map { pasteboardItem in
            let representations = pasteboardItem.types.reduce(
                into: [NSPasteboard.PasteboardType: Data]()
            ) { result, type in
                result[type] = pasteboardItem.data(forType: type)
            }
            return Item(representations: representations)
        }
    }

    init(archivedItems: [[NSPasteboard.PasteboardType: Data]]) {
        items = archivedItems.map(Item.init(representations:))
    }

    func makePasteboardItems() -> [NSPasteboardItem] {
        items.map { archivedItem in
            let item = NSPasteboardItem()
            for (type, data) in archivedItem.representations {
                item.setData(data, forType: type)
            }
            return item
        }
    }
}

enum InputSourceClassifier {
    private static let knownCJKPrefixes = [
        "com.apple.inputmethod.SCIM",
        "com.apple.inputmethod.TCIM",
        "com.apple.inputmethod.Kotoeri",
        "com.apple.inputmethod.Korean",
    ]

    static func isCJK(sourceID: String, languages: [String]) -> Bool {
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

/// Handles text injection into the currently focused input field.
/// Saves/restores clipboard, detects CJK input methods, switches to ASCII if needed,
/// and simulates Cmd+V paste.
@MainActor
final class TextInjector {
    // MARK: - Properties

    /// Brief delay (seconds) after paste before restoring state
    private let pasteDelay: UInt64 = 150_000_000  // 150ms in nanoseconds

    // MARK: - Public

    func inject(_ text: String) async -> InjectionResult {
        guard !text.isEmpty else { return .success }

        // 1. Check accessibility permission
        guard AXIsProcessTrusted() else {
            return .permissionDenied
        }

        // 2. Save current state
        let savedClipboard = saveClipboard()
        let savedInputSource = getCurrentInputSource()
        let wasCJK = isCJKInputSource(savedInputSource)

        // 3. Switch to ASCII if needed
        let switchedInputSource = wasCJK && switchToASCIIInputSource()
        if switchedInputSource {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms for input source switch
        }

        // 4. Copy text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 5. Simulate Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            // Event creation failed — leave text on clipboard as fallback
            if switchedInputSource, let savedSource = savedInputSource {
                restoreInputSource(savedSource)
            }
            return .eventCreationFailed
        }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)

        // 6. Wait briefly for paste to complete
        try? await Task.sleep(nanoseconds: pasteDelay)

        // 7. Restore input source
        if switchedInputSource, let savedSource = savedInputSource {
            restoreInputSource(savedSource)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // 8. Restore clipboard
        restoreClipboard(savedClipboard)

        return .success
    }

    // MARK: - Clipboard

    private func saveClipboard() -> PasteboardSnapshot {
        PasteboardSnapshot(items: NSPasteboard.general.pasteboardItems ?? [])
    }

    private func restoreClipboard(_ saved: PasteboardSnapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let items = saved.makePasteboardItems()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    // MARK: - Input Source Detection

    private func getCurrentInputSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func isCJKInputSource(_ source: TISInputSource?) -> Bool {
        guard let source = source else { return false }

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

    // MARK: - Input Source Switching

    private func switchToASCIIInputSource() -> Bool {
        guard let asciiSource = findASCIIInputSource() else {
            return false
        }
        return TISSelectInputSource(asciiSource) == noErr
    }

    private func findASCIIInputSource() -> TISInputSource? {
        // Common ASCII input source IDs to try
        let asciiIDs = [
            "com.apple.keylayout.ABC",      // macOS 14+ ABC layout
            "com.apple.keylayout.US",       // US layout
            "com.apple.keylayout.British",  // British layout
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

        // Verify it's a keyboard layout (not an input method)
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
