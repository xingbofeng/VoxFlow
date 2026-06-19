import AppKit
import Foundation
import VoxFlowTextInsertion

// MARK: - ClipboardSetting

@MainActor
protocol ClipboardSetting: AnyObject {
    @discardableResult
    func setString(_ text: String) -> Bool
}

@MainActor
final class SystemClipboardService: ClipboardSetting {
    @discardableResult
    func setString(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
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
        if mode == .agentCompose {
            let result: OutputResult = clipboardService.setString(text)
                ? .copied
                : .copyFailed(reason: "Clipboard write failed")
            return logged(result, mode: mode, textInputMode: textInputMode)
        }

        if targetChanged(original: originalTarget, current: target) {
            guard clipboardService.setString(text) else {
                let result = OutputResult.copyFailed(
                    reason: "Target changed and clipboard write failed"
                )
                rememberLastResult(text, mode: mode, result: result)
                return logged(result, mode: mode, textInputMode: textInputMode)
            }
            let reason = buildChangeReason(original: originalTarget, current: target)
            let result = OutputResult.targetChanged(reason: reason)
            rememberLastResult(text, mode: mode, result: result)
            return logged(result, mode: mode, textInputMode: textInputMode)
        }

        let result = await textInsertionCoordinator.insert(text, mode: textInputMode)
        let outputResult: OutputResult = switch result {
        case .success:
            .injected
        case .permissionDenied:
            clipboardService.setString(text)
                ? .permissionDenied(reason: "Accessibility permission denied")
                : .copyFailed(reason: "Accessibility permission denied and clipboard write failed")
        case .eventCreationFailed:
            clipboardService.setString(text)
                ? .injectionFailed(reason: "Failed to create paste event")
                : .copyFailed(reason: "Failed to create paste event and clipboard write failed")
        case .cancelled:
            .cancelled
        case .unavailable(let reason):
            clipboardService.setString(text)
                ? .injectionFailed(reason: reason)
                : .copyFailed(reason: "\(reason) and clipboard write failed")
        }
        rememberLastResult(text, mode: mode, result: outputResult)
        return logged(outputResult, mode: mode, textInputMode: textInputMode)
    }

    func deliverToInAppTextTarget(
        text: String,
        target: InAppTextOutputTarget
    ) -> OutputResult {
        rememberLastResult(text, mode: .dictation, result: .injected)
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

    private func rememberLastResult(
        _ text: String,
        mode: VoiceTaskMode,
        result: OutputResult
    ) {
        guard mode == .dictation else { return }
        guard result != .cancelled else { return }
        lastResultStore?.setLastResultText(text)
    }

    private func logged(
        _ result: OutputResult,
        mode: VoiceTaskMode,
        textInputMode: TextInputMode
    ) -> OutputResult {
        AppLogger.general.info(
            "text_output_delivered mode=\(mode.rawValue) textInputMode=\(textInputMode.rawValue) result=\(outputResultLabel(result))"
        )
        return result
    }

    private func outputResultLabel(_ result: OutputResult) -> String {
        switch result {
        case .injected:
            return "injected"
        case .copied:
            return "copied"
        case .targetChanged:
            return "targetChanged"
        case .permissionDenied:
            return "permissionDenied"
        case .injectionFailed:
            return "injectionFailed"
        case .copyFailed:
            return "copyFailed"
        case .cancelled:
            return "cancelled"
        }
    }
}
