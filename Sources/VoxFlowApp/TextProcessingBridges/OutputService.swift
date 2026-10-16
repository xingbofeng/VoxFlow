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
    private let internalWriteGuard: ClipboardInternalWriteGuard?
    private let pasteboard: NSPasteboard

    init(
        internalWriteGuard: ClipboardInternalWriteGuard? = nil,
        pasteboard: NSPasteboard? = nil
    ) {
        self.internalWriteGuard = internalWriteGuard
        self.pasteboard = pasteboard ?? Self.defaultPasteboard()
    }

    @discardableResult
    func setString(_ text: String) -> Bool {
        if let internalWriteGuard {
            return internalWriteGuard.writeInternalString(text, to: pasteboard)
        }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    func setImage(_ image: CGImage) -> Bool {
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let wroteImage = pasteboard.writeObjects([nsImage])
        if wroteImage {
            internalWriteGuard?.markInternalWrite(changeCount: pasteboard.changeCount)
        }
        return wroteImage
    }

    private static func defaultPasteboard() -> NSPasteboard {
        guard isRunningUnderXCTest else { return .general }
        let name = NSPasteboard.Name("SystemClipboardServiceTests-\(UUID().uuidString)")
        return NSPasteboard(name: name)
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }
}

extension SystemClipboardService: ScreenshotOCRResultClipboard {}

// MARK: - OutputService

@MainActor
protocol OutputService: AnyObject {
    func copy(text: String, mode: VoiceTaskMode) async -> OutputResult

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult

    /// Replaces the whole content of the focused input area with `text`.
    ///
    /// Only used by voice commands: `expectedInputText` is the snapshot taken
    /// when recording started, and delivery is refused (the result is copied
    /// instead) when the field no longer holds it.
    func deliverReplacingInputArea(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        expectedInputText: String
    ) async -> OutputResult
}

extension OutputService {
    func copy(text: String, mode: VoiceTaskMode) async -> OutputResult {
        await deliver(text: text, mode: .agentCompose, target: nil, originalTarget: nil)
    }

    /// Delivery that cannot replace field contents (test doubles, in-app
    /// targets) falls back to a plain insertion.
    func deliverReplacingInputArea(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        expectedInputText: String
    ) async -> OutputResult {
        await deliver(text: text, mode: mode, target: target, originalTarget: originalTarget)
    }
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
    private let outputMethodRuleStore: OutputMethodRuleStore

    init(settingsRepository: any SettingsRepository) {
        self.settingsRepository = settingsRepository
        self.outputMethodRuleStore = OutputMethodRuleStore(settingsRepository: settingsRepository)
    }

    func textInputMode(for target: DictationTarget?) -> TextInputMode {
        let globalMode: TextInputMode
        if let rawValue = string(forKey: SettingsKey.outputTextInputMode),
           let mode = TextInputMode(rawValue: rawValue) {
            globalMode = mode
        } else {
            globalMode = bool(
                forKey: SettingsSystemOption.avoidClipboard.rawValue,
                defaultValue: SettingsSystemOption.avoidClipboard.defaultValue
            ) ? .simulatedTyping : .automatic
        }
        return outputMethodRuleStore.inputMode(for: target, fallback: globalMode)
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

// MARK: - OutputMethodRule

struct OutputMethodRule: Codable, Equatable, Identifiable {
    let id: String
    let bundleID: String
    let appName: String
    let inputMode: TextInputMode
}

final class OutputMethodRuleStore {
    private struct Payload: Codable {
        let rules: [OutputMethodRule]
    }

    static let settingsKey = "output.appMethodRules"

    private let settingsRepository: any SettingsRepository

    init(settingsRepository: any SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func list() throws -> [OutputMethodRule] {
        guard let json = try settingsRepository.value(forKey: Self.settingsKey),
              let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode(Payload.self, from: data).rules) ?? []
    }

    func save(_ rule: OutputMethodRule) throws {
        var rules = try list().filter { $0.id != rule.id }
        let ruleBundleID = Self.normalized(rule.bundleID)
        if let ruleBundleID {
            rules.removeAll { Self.normalized($0.bundleID) == ruleBundleID }
        }
        rules.append(rule)
        try write(rules)
    }

    func delete(id: String) throws {
        try write(try list().filter { $0.id != id })
    }

    func inputMode(for target: DictationTarget?, fallback: TextInputMode) -> TextInputMode {
        guard let target else { return fallback }
        let rules = (try? list()) ?? []
        if let bundleID = Self.normalized(target.bundleID),
           let rule = rules.first(where: { Self.normalized($0.bundleID) == bundleID }) {
            return rule.inputMode
        }
        if let appName = Self.normalized(target.appName),
           let rule = rules.first(where: { Self.normalized($0.appName) == appName }) {
            return rule.inputMode
        }
        return fallback
    }

    private func write(_ rules: [OutputMethodRule]) throws {
        let data = try JSONEncoder().encode(Payload(rules: rules))
        try settingsRepository.set(Self.settingsKey, jsonValue: String(data: data, encoding: .utf8) ?? #"{"rules":[]}"#)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

// MARK: - OutputPolicy

enum OutputPolicyCopyReason: Equatable {
    case agentCompose
    case targetChanged(String)
}

enum OutputPolicyAction: Equatable {
    case copy(reason: OutputPolicyCopyReason)
    case insert
}

struct DefaultOutputPolicy {
    func action(
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) -> OutputPolicyAction {
        if mode == .agentCompose {
            return .copy(reason: .agentCompose)
        }

        if DictationTargetChangePolicy.targetChanged(original: originalTarget, current: target) {
            return .copy(reason: .targetChanged(changeReason(original: originalTarget, current: target)))
        }

        return .insert
    }

    private func changeReason(
        original: DictationTarget?,
        current: DictationTarget?
    ) -> String {
        if original?.bundleID != current?.bundleID {
            return "Target application changed from \(original?.appName ?? "unknown") to \(current?.appName ?? "unknown")"
        }
        return "Target window changed"
    }
}

// MARK: - DefaultOutputService

@MainActor
final class DefaultOutputService: OutputService, NotesOutputDelivering {
    /// Settle time between selecting the field's contents and pasting over
    /// them, so apps that apply the selection asynchronously do not paste at
    /// the old caret position.
    static let selectAllSettleNanoseconds: UInt64 = 50_000_000

    private let textInsertionCoordinator: any TextInsertionCoordinating
    private let clipboardService: any ClipboardSetting
    private let textInputModeProvider: (DictationTarget?) -> TextInputMode
    private let outputPolicy: DefaultOutputPolicy
    private let lastResultStore: (any LastResultStoring)?
    private let recentTextOutputRecorder: ((String, DictationTarget?) -> Void)?
    private let selectAllShortcutPoster: any SelectAllShortcutPosting
    private let inputAreaTextProvider: (@MainActor (DictationTarget?) -> String?)?
    private let selectAllSettleNanoseconds: UInt64

    init(
        textInsertionCoordinator: any TextInsertionCoordinating,
        clipboardService: any ClipboardSetting,
        defaultTextInputMode: TextInputMode = .automatic,
        textInputMode: ((DictationTarget?) -> TextInputMode)? = nil,
        outputPolicy: DefaultOutputPolicy = DefaultOutputPolicy(),
        lastResultStore: (any LastResultStoring)? = nil,
        recentTextOutputRecorder: ((String, DictationTarget?) -> Void)? = nil,
        selectAllShortcutPoster: any SelectAllShortcutPosting = SystemSelectAllShortcutPoster(),
        inputAreaTextProvider: (@MainActor (DictationTarget?) -> String?)? = nil,
        selectAllSettleNanoseconds: UInt64 = DefaultOutputService.selectAllSettleNanoseconds
    ) {
        self.textInsertionCoordinator = textInsertionCoordinator
        self.clipboardService = clipboardService
        self.textInputModeProvider = textInputMode ?? { _ in defaultTextInputMode }
        self.outputPolicy = outputPolicy
        self.lastResultStore = lastResultStore
        self.recentTextOutputRecorder = recentTextOutputRecorder
        self.selectAllShortcutPoster = selectAllShortcutPoster
        self.inputAreaTextProvider = inputAreaTextProvider
        self.selectAllSettleNanoseconds = selectAllSettleNanoseconds
    }

    convenience init(
        textInjector: any TextInserting,
        clipboardService: any ClipboardSetting,
        defaultTextInputMode: TextInputMode = .automatic,
        textInputMode: ((DictationTarget?) -> TextInputMode)? = nil,
        outputPolicy: DefaultOutputPolicy = DefaultOutputPolicy(),
        lastResultStore: (any LastResultStoring)? = nil,
        recentTextOutputRecorder: ((String, DictationTarget?) -> Void)? = nil,
        selectAllShortcutPoster: any SelectAllShortcutPosting = SystemSelectAllShortcutPoster(),
        inputAreaTextProvider: (@MainActor (DictationTarget?) -> String?)? = nil,
        selectAllSettleNanoseconds: UInt64 = DefaultOutputService.selectAllSettleNanoseconds
    ) {
        self.init(
            textInsertionCoordinator: TextInsertionCoordinator(fastPasteInserter: textInjector),
            clipboardService: clipboardService,
            defaultTextInputMode: defaultTextInputMode,
            textInputMode: textInputMode,
            outputPolicy: outputPolicy,
            lastResultStore: lastResultStore,
            recentTextOutputRecorder: recentTextOutputRecorder,
            selectAllShortcutPoster: selectAllShortcutPoster,
            inputAreaTextProvider: inputAreaTextProvider,
            selectAllSettleNanoseconds: selectAllSettleNanoseconds
        )
    }

    func copy(text: String, mode: VoiceTaskMode) async -> OutputResult {
        guard !Task.isCancelled else { return .cancelled }
        let result: OutputResult = clipboardService.setString(text)
            ? .copied
            : .copyFailed(reason: "Clipboard write failed")
        rememberLastResult(text, mode: mode, result: result)
        return logged(
            result, mode: mode, textInputMode: textInputModeProvider(nil),
            originalTarget: nil, currentTarget: nil
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
            textInputMode: textInputModeProvider(target)
        )
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        textInputMode: TextInputMode
    ) async -> OutputResult {
        switch outputPolicy.action(mode: mode, target: target, originalTarget: originalTarget) {
        case .copy(reason: .agentCompose):
            let outputResult: OutputResult = clipboardService.setString(text)
                ? .copied
                : .copyFailed(reason: "Clipboard write failed")
            rememberLastResult(text, mode: mode, result: outputResult)
            return logged(
                outputResult,
                mode: mode,
                textInputMode: textInputMode,
                originalTarget: originalTarget,
                currentTarget: target
            )

        case .copy(reason: .targetChanged(let reason)):
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
            let result = OutputResult.targetChanged(reason: reason)
            rememberLastResult(text, mode: mode, result: result)
            return logged(
                result,
                mode: mode,
                textInputMode: textInputMode,
                originalTarget: originalTarget,
                currentTarget: target
            )

        case .insert:
            break
        }

        return await insertIntoFocusedField(
            text,
            mode: mode,
            textInputMode: textInputMode,
            target: target,
            originalTarget: originalTarget
        )
    }

    func deliverReplacingInputArea(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        expectedInputText: String
    ) async -> OutputResult {
        await deliverReplacingInputArea(
            text: text,
            mode: mode,
            target: target,
            originalTarget: originalTarget,
            expectedInputText: expectedInputText,
            textInputMode: textInputModeProvider(target)
        )
    }

    func deliverReplacingInputArea(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        expectedInputText: String,
        textInputMode: TextInputMode
    ) async -> OutputResult {
        guard !Task.isCancelled else { return .cancelled }
        switch outputPolicy.action(mode: mode, target: target, originalTarget: originalTarget) {
        case .copy:
            // The destination is not the one we read from: never replace
            // anything, fall back to the regular copy delivery.
            return await deliver(
                text: text,
                mode: mode,
                target: target,
                originalTarget: originalTarget,
                textInputMode: textInputMode
            )
        case .insert:
            break
        }

        if let inputAreaTextProvider,
           inputAreaTextProvider(target) != expectedInputText {
            let reason = "Input area text changed since it was read"
            let outputResult: OutputResult = clipboardService.setString(text)
                ? .inputChanged(reason: reason)
                : .copyFailed(reason: "\(reason) and clipboard write failed")
            rememberLastResult(text, mode: mode, result: outputResult)
            return logged(
                outputResult,
                mode: mode,
                textInputMode: textInputMode,
                originalTarget: originalTarget,
                currentTarget: target
            )
        }

        do {
            try selectAllShortcutPoster.postSelectAllShortcut()
        } catch {
            let reason = "Failed to create select-all event"
            let outputResult: OutputResult = clipboardService.setString(text)
                ? .injectionFailed(reason: reason)
                : .copyFailed(reason: "\(reason) and clipboard write failed")
            rememberLastResult(text, mode: mode, result: outputResult)
            return logged(
                outputResult,
                mode: mode,
                textInputMode: textInputMode,
                originalTarget: originalTarget,
                currentTarget: target
            )
        }

        if selectAllSettleNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: selectAllSettleNanoseconds)
            } catch {
                return .cancelled
            }
        }
        guard !Task.isCancelled else { return .cancelled }
        return await insertIntoFocusedField(
            text,
            mode: mode,
            textInputMode: textInputMode,
            target: target,
            originalTarget: originalTarget
        )
    }

    private func insertIntoFocusedField(
        _ text: String,
        mode: VoiceTaskMode,
        textInputMode: TextInputMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        guard !Task.isCancelled else { return .cancelled }
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
        recordRecentTextOutputIfNeeded(text, result: outputResult, target: target)
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
            textInputMode: textInputModeProvider(nil)
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
        recordRecentTextOutputIfNeeded(text, result: outputResult, target: nil)
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

    private func rememberLastResult(
        _ text: String,
        mode: VoiceTaskMode,
        result: OutputResult
    ) {
        guard mode == .dictation else { return }
        guard result != .cancelled else { return }
        lastResultStore?.setLastResultText(text)
    }

    private func recordRecentTextOutputIfNeeded(
        _ text: String,
        result: OutputResult,
        target: DictationTarget?
    ) {
        guard result.kind == .inserted else { return }
        recentTextOutputRecorder?(text, target)
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
        case .inputChanged:
            return "inputChanged"
        case .permissionDenied:
            return "permissionDenied"
        case .injectionFailed:
            return "injectionFailed"
        case .copyFailed:
            return "copyFailed"
        case .handledExternally:
            return "handledExternally"
        case .cancelled:
            return "cancelled"
        }
    }

    private func fallbackReason(for result: OutputResult) -> String {
        switch result {
        case .injected, .copied, .handledExternally, .cancelled:
            return "none"
        case let .targetChanged(reason),
             let .inputChanged(reason),
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
