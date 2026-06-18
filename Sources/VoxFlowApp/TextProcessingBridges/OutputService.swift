import AppKit
import Foundation
import VoxFlowTextInsertion

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

@MainActor
struct InAppTextOutputTarget {
    private let writer: (String) -> Void

    init(write: @escaping (String) -> Void) {
        self.writer = write
    }

    func write(_ text: String) {
        writer(text)
    }
}

@MainActor
protocol NotesOutputDelivering: AnyObject {
    func deliverToInAppTextTarget(
        text: String,
        target: InAppTextOutputTarget
    ) -> OutputResult
}

// MARK: - DefaultOutputService

@MainActor
final class DefaultOutputService: OutputService, NotesOutputDelivering {
    private let textInsertionCoordinator: any TextInsertionCoordinating
    private let clipboardService: any ClipboardSetting
    private let defaultTextInputMode: TextInputMode
    private let lastResultStore: (any LastResultStoring)?

    init(
        textInsertionCoordinator: any TextInsertionCoordinating,
        clipboardService: any ClipboardSetting,
        defaultTextInputMode: TextInputMode = .automatic,
        lastResultStore: (any LastResultStoring)? = nil
    ) {
        self.textInsertionCoordinator = textInsertionCoordinator
        self.clipboardService = clipboardService
        self.defaultTextInputMode = defaultTextInputMode
        self.lastResultStore = lastResultStore
    }

    convenience init(
        textInjector: any TextInserting,
        clipboardService: any ClipboardSetting,
        defaultTextInputMode: TextInputMode = .automatic,
        lastResultStore: (any LastResultStoring)? = nil
    ) {
        self.init(
            textInsertionCoordinator: TextInsertionCoordinator(fastPasteInserter: textInjector),
            clipboardService: clipboardService,
            defaultTextInputMode: defaultTextInputMode,
            lastResultStore: lastResultStore
        )
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        await deliver(
            text: text,
            mode: mode,
            target: target,
            originalTarget: originalTarget,
            textInputMode: defaultTextInputMode
        )
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        textInputMode: TextInputMode
    ) async -> OutputResult {
        rememberLastResult(text)

        if mode == .agentCompose {
            clipboardService.setString(text)
            return .copied
        }

        if targetChanged(original: originalTarget, current: target) {
            clipboardService.setString(text)
            let reason = buildChangeReason(original: originalTarget, current: target)
            return .targetChanged(reason: reason)
        }

        let result = await textInsertionCoordinator.insert(text, mode: textInputMode)
        switch result {
        case .success:
            return .injected
        case .permissionDenied:
            clipboardService.setString(text)
            return .permissionDenied(reason: "Accessibility permission denied")
        case .eventCreationFailed:
            // Text is already on clipboard from the injection attempt
            return .injectionFailed(reason: "Failed to create paste event")
        case .cancelled:
            return .cancelled
        case .unavailable(let reason):
            return .injectionFailed(reason: reason)
        }
    }

    func deliverToInAppTextTarget(
        text: String,
        target: InAppTextOutputTarget
    ) -> OutputResult {
        rememberLastResult(text)
        target.write(text)
        return .injected
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

    private func rememberLastResult(_ text: String) {
        lastResultStore?.setLastResultText(text)
    }
}
