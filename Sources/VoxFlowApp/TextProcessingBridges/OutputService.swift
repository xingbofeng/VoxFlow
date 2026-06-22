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
protocol ScreenshotImageClipboardWriting: AnyObject {
    @discardableResult
    func setImage(_ image: CGImage) -> Bool
}

@MainActor
protocol ScreenshotOCRResultClipboard: ClipboardSetting, ScreenshotImageClipboardWriting {}

@MainActor
final class SystemClipboardService: ClipboardSetting, ScreenshotImageClipboardWriting {
    @discardableResult
    func setString(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    func setImage(_ image: CGImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        return pasteboard.writeObjects([nsImage])
    }
}

extension SystemClipboardService: ScreenshotOCRResultClipboard {}

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

@MainActor
struct SettingsBackedTextOutputConfiguration {
    private let settingsRepository: any SettingsRepository

    init(settingsRepository: any SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func textInputMode() -> TextInputMode {
        if let rawValue = string(forKey: SettingsKey.outputTextInputMode),
           let mode = TextInputMode(rawValue: rawValue) {
            return mode
        }
        return bool(
            forKey: SettingsSystemOption.avoidClipboard.rawValue,
            defaultValue: SettingsSystemOption.avoidClipboard.defaultValue
        ) ? .simulatedTyping : .automatic
    }

    func shouldRestoreClipboard() -> Bool {
        bool(
            forKey: SettingsSystemOption.restoreClipboard.rawValue,
            defaultValue: SettingsSystemOption.restoreClipboard.defaultValue
        )
    }

    private func string(forKey key: String) -> String? {
        guard let jsonString = try? settingsRepository.value(forKey: key),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(DecodedSettingValue<String>.self, from: data).value
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard let jsonString = try? settingsRepository.value(forKey: key),
              let data = jsonString.data(using: .utf8) else {
            return defaultValue
        }
        return (try? JSONDecoder().decode(DecodedSettingValue<Bool>.self, from: data).value) ?? defaultValue
    }
}

// MARK: - DefaultOutputService

@MainActor
final class DefaultOutputService: OutputService, NotesOutputDelivering {
    private let textInsertionCoordinator: any TextInsertionCoordinating
    private let clipboardService: any ClipboardSetting
    private let textInputModeProvider: () -> TextInputMode
    private let lastResultStore: (any LastResultStoring)?

    init(
        textInsertionCoordinator: any TextInsertionCoordinating,
        clipboardService: any ClipboardSetting,
        defaultTextInputMode: TextInputMode = .automatic,
        textInputMode: (() -> TextInputMode)? = nil,
        lastResultStore: (any LastResultStoring)? = nil
    ) {
        self.textInsertionCoordinator = textInsertionCoordinator
        self.clipboardService = clipboardService
        self.textInputModeProvider = textInputMode ?? { defaultTextInputMode }
        self.lastResultStore = lastResultStore
    }

    convenience init(
        textInjector: any TextInserting,
        clipboardService: any ClipboardSetting,
        defaultTextInputMode: TextInputMode = .automatic,
        textInputMode: (() -> TextInputMode)? = nil,
        lastResultStore: (any LastResultStoring)? = nil
    ) {
        self.init(
            textInsertionCoordinator: TextInsertionCoordinator(fastPasteInserter: textInjector),
            clipboardService: clipboardService,
            defaultTextInputMode: defaultTextInputMode,
            textInputMode: textInputMode,
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
            textInputMode: textInputModeProvider()
        )
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        textInputMode: TextInputMode
    ) async -> OutputResult {
        if targetChanged(original: originalTarget, current: target) {
            guard clipboardService.setString(text) else {
                let result = OutputResult.copyFailed(
                    reason: "Target changed and clipboard write failed"
                )
                rememberLastResult(text, mode: mode, result: result)
                return logged(
                    result,
                    mode: mode,
                    textInputMode: textInputMode,
                    originalTarget: originalTarget,
                    currentTarget: target
                )
            }
            let reason = buildChangeReason(original: originalTarget, current: target)
            let result = OutputResult.targetChanged(reason: reason)
            rememberLastResult(text, mode: mode, result: result)
            return logged(
                result,
                mode: mode,
                textInputMode: textInputMode,
                originalTarget: originalTarget,
                currentTarget: target
            )
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
        return logged(
            outputResult,
            mode: mode,
            textInputMode: textInputMode,
            originalTarget: originalTarget,
            currentTarget: target
        )
    }

    func deliverInputOnly(
        text: String,
        mode: VoiceTaskMode
    ) async -> OutputResult {
        await deliverInputOnly(
            text: text,
            mode: mode,
            textInputMode: textInputModeProvider()
        )
    }

    func deliverInputOnly(
        text: String,
        mode: VoiceTaskMode,
        textInputMode: TextInputMode
    ) async -> OutputResult {
        let result = await textInsertionCoordinator.insert(text, mode: textInputMode)
        let outputResult: OutputResult = switch result {
        case .success:
            .injected
        case .permissionDenied:
            .permissionDenied(reason: "Accessibility permission denied")
        case .eventCreationFailed:
            .injectionFailed(reason: "Failed to create paste event")
        case .cancelled:
            .cancelled
        case .unavailable(let reason):
            .injectionFailed(reason: reason)
        }
        rememberLastResult(text, mode: mode, result: outputResult)
        return logged(
            outputResult,
            mode: mode,
            textInputMode: textInputMode,
            originalTarget: nil,
            currentTarget: nil
        )
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
        textInputMode: TextInputMode,
        originalTarget: DictationTarget?,
        currentTarget: DictationTarget?
    ) -> OutputResult {
        AppLogger.general.info(
            "text_output_delivered mode=\(mode.rawValue) textInputMode=\(textInputMode.rawValue) result=\(outputResultLabel(result)) outputKind=\(result.kind.rawValue) originalTarget=\(Self.logDescription(for: originalTarget)) currentTarget=\(Self.logDescription(for: currentTarget)) fallbackReason=\(fallbackReason(for: result))"
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

    private func fallbackReason(for result: OutputResult) -> String {
        switch result {
        case .injected, .copied, .cancelled:
            return "none"
        case let .targetChanged(reason),
             let .permissionDenied(reason),
             let .injectionFailed(reason),
             let .copyFailed(reason):
            return reason
        }
    }

    private static func logDescription(for target: DictationTarget?) -> String {
        guard let target else { return "nil" }
        let hasWindowTitle = target.windowTitle?.isEmpty == false
        return "{bundleID=\(target.bundleID ?? "nil"),appName=\(target.appName ?? "nil"),pid=\(target.pid.map { String($0) } ?? "nil"),windowID=\(target.windowID ?? "nil"),hasWindowTitle=\(hasWindowTitle)}"
    }
}
