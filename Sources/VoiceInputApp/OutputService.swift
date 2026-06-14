import AppKit
import Foundation

// MARK: - ClipboardSetting

@MainActor
protocol ClipboardSetting: AnyObject {
    func setString(_ text: String)
}

@MainActor
final class SystemClipboardService: ClipboardSetting {
    func setString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - OutputService

@MainActor
protocol OutputService: AnyObject {
    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult
}

// MARK: - DefaultOutputService

@MainActor
final class DefaultOutputService: OutputService {
    private let textInjector: any TextInjecting
    private let clipboardService: any ClipboardSetting

    init(
        textInjector: any TextInjecting,
        clipboardService: any ClipboardSetting
    ) {
        self.textInjector = textInjector
        self.clipboardService = clipboardService
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        // Agent compose always copies to clipboard
        if mode == .agentCompose {
            clipboardService.setString(text)
            return .copied
        }

        // Dictation mode: check if target changed
        if targetChanged(original: originalTarget, current: target) {
            clipboardService.setString(text)
            let reason = buildChangeReason(original: originalTarget, current: target)
            return .targetChanged(reason: reason)
        }

        // Target unchanged — attempt injection
        let result = await textInjector.inject(text)
        switch result {
        case .success:
            return .injected
        case .permissionDenied:
            clipboardService.setString(text)
            return .injectionFailed(reason: "Accessibility permission denied")
        case .eventCreationFailed:
            // Text is already on clipboard from the injection attempt
            return .injectionFailed(reason: "Failed to create paste event")
        case .cancelled:
            return .cancelled
        }
    }

    // MARK: - Private

    private func targetChanged(
        original: DictationTarget?,
        current: DictationTarget?
    ) -> Bool {
        DictationTargetChangePolicy.targetChanged(original: original, current: current)
    }

    private func buildChangeReason(
        original: DictationTarget?,
        current: DictationTarget?
    ) -> String {
        if original?.bundleID != current?.bundleID {
            return "Target application changed from \(original?.appName ?? "unknown") to \(current?.appName ?? "unknown")"
        }
        return "Target window changed"
    }
}
