import Foundation
@preconcurrency import Speech
import Shared
import UIKit
import VoxFlowASRRuntime
import VoxFlowMobileCore
import VoxFlowProviderApple

/// 用户可选的 ASR Provider。Apple Speech 为 baseline，三家云 Provider 为 LiveContainer 主验收路径。
enum SelectedProvider: String, CaseIterable, Identifiable {
    case appleSpeech = "apple_speech"
    case tencent = "tencent"
    case aliyun = "aliyun"
    case volcengine = "volcengine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return L10n.t("provider.apple_speech")
        case .tencent: return L10n.t("provider.tencent")
        case .aliyun: return L10n.t("provider.aliyun")
        case .volcengine: return L10n.t("provider.volcengine")
        }
    }

    var summaryKey: String {
        switch self {
        case .appleSpeech: return "provider.summary.apple_speech"
        case .tencent: return "provider.summary.tencent"
        case .aliyun: return "provider.summary.aliyun"
        case .volcengine: return "provider.summary.volcengine"
        }
    }

    var requiresCredentials: Bool {
        switch self {
        case .appleSpeech: return false
        case .tencent, .aliyun, .volcengine: return true
        }
    }

    var credentialProvider: LocalCredentialStore.Provider? {
        switch self {
        case .appleSpeech: return nil
        case .tencent: return .tencent
        case .aliyun: return .aliyun
        case .volcengine: return .volcengine
        }
    }
}

/// 用户可选的识别语言。映射到 BCP47 tag，用于 ASR engine configure。
enum SelectedLanguage: String, CaseIterable, Identifiable {
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case enUS = "en-US"
    case jaJP = "ja-JP"
    case koKR = "ko-KR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhCN: return L10n.t("language.zh-CN")
        case .zhTW: return L10n.t("language.zh-TW")
        case .enUS: return L10n.t("language.en-US")
        case .jaJP: return L10n.t("language.ja-JP")
        case .koKR: return L10n.t("language.ko-KR")
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

/// 诊断时间线条目。记录音频、网络、ASR、权限相关事件，用于 DiagnosticsView 展示。
struct TimelineEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let category: Category
    let message: String

    enum Category: String {
        case audio
        case network
        case asr
        case permission
        case env
    }
}

/// iOS App 中心状态。持有 MobileDictationSession、录音器、凭证存储和诊断数据。
///
/// 所有 UI mutation 在 MainActor 上；ASR/录音回调通过 onChange/onPermissionDenied 进入主线程。
@MainActor
final class AppState: ObservableObject {
    @Published var selectedProvider: SelectedProvider {
        didSet { Self.persistProvider(selectedProvider) }
    }
    @Published var selectedLanguage: SelectedLanguage {
        didSet { Self.persistLanguage(selectedLanguage) }
    }
    @Published var sessionState: MobileDictationState = .idle
    @Published var finalText: String = ""
    @Published var timelineEvents: [TimelineEvent] = []
    @Published var credentialValues: [LocalCredentialStore.Provider: LocalCredentialStore.CredentialValues] = [:]
    @Published var recorderDiagnostic: RecorderDiagnostic = .init()
    @Published var appleSpeechAuthorization: AppleSpeechAuthorizationStatus = .notDetermined
    @Published var waveformEnergy: [Float] = []

    /// True when the app should present the ClipboardDictationHandoffView.
    /// Set ONLY by the `mashangxie://dictation/clipboard-start` deep link —
    /// normal app launches do NOT restore this state (per spec).
    @Published var clipboardHandoffActive: Bool = false
    @Published var clipboardHandoffPresentationID = UUID()

    let credentialStore = LocalCredentialStore()

    private var session: MobileDictationSession?
    private var recorder: iOSAudioRecorder?

    private static let providerKey = "VoxFlowiOS.selectedProvider"
    private static let languageKey = "VoxFlowiOS.selectedLanguage"

    init() {
        let providerRaw = AppGroup.preferences.string(forKey: SharedKeys.provider)
            ?? UserDefaults.standard.string(forKey: Self.providerKey)
            ?? SelectedProvider.appleSpeech.rawValue
        let languageRaw = UserDefaults.standard.string(forKey: Self.languageKey) ?? SelectedLanguage.zhCN.rawValue
        self.selectedProvider = SelectedProvider(rawValue: providerRaw) ?? .appleSpeech
        self.selectedLanguage = SelectedLanguage(rawValue: languageRaw) ?? .zhCN
        self.credentialValues = credentialStore.loadAll()
        self.appleSpeechAuthorization = Self.currentAppleSpeechAuthorization()
        Self.persistProvider(selectedProvider)
        Self.persistLanguage(selectedLanguage)
        Self.persistKeyboardDefaults()
    }

    // MARK: - Dictation

    /// 当前 live text（来自 partial 或 final），供调试和诊断界面展示。
    var visibleLiveText: String {
        switch sessionState {
        case let .recording(liveText), let .transcribing(liveText):
            return liveText
        case let .finished(text):
            return text
        default:
            return ""
        }
    }

    func startDictation() async {
        discardCurrentDictationSession()
        appendTimeline(.audio, message: L10n.t("timeline.start_requested"))
        if selectedProvider == .appleSpeech {
            await refreshAppleSpeechAuthorization(requestIfNeeded: true)
            guard appleSpeechAuthorization == .authorized else {
                let message = L10n.t(appleSpeechAuthorization == .denied
                    ? "diagnostics.availability.permission_denied"
                    : "diagnostics.availability.permission_not_determined")
                sessionState = .failed(message: message)
                appendTimeline(.permission, message: message)
                return
            }
        }

        let engine: ASREngine
        do {
            engine = try makeEngine(for: selectedProvider)
        } catch {
            sessionState = .failed(message: error.localizedDescription)
            appendTimeline(.asr, message: L10n.t("timeline.engine_build_failed", error.localizedDescription))
            return
        }

        let recorder = iOSAudioRecorder()
        recorder.onInterruption = { [weak self] in
            Task { @MainActor in
                self?.appendTimeline(.audio, message: L10n.t("timeline.interruption"))
                self?.sessionState = .failed(message: L10n.t("error.interruption"))
            }
        }
        recorder.onRouteChangeEnded = { [weak self] in
            Task { @MainActor in
                self?.appendTimeline(.audio, message: L10n.t("timeline.route_change"))
                self?.sessionState = .failed(message: L10n.t("error.route_change"))
            }
        }
        recorder.onWaveform = { [weak self] energy in
            Task { @MainActor in
                self?.waveformEnergy = energy
            }
        }
        self.recorder = recorder

        let session = MobileDictationSession(engine: engine, recorder: recorder)
        session.onChange = { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
            }
        }
        session.onPermissionDenied = { [weak self] in
            Task { @MainActor in
                self?.appendTimeline(.permission, message: L10n.t("timeline.permission_denied"))
            }
        }
        self.session = session
        appleSpeechAuthorization = Self.currentAppleSpeechAuthorization()
        await session.start()
    }

    func stopDictation() {
        appendTimeline(.audio, message: L10n.t("timeline.stop_requested"))
        session?.stop()
    }

    func cancelDictation() {
        discardCurrentDictationSession()
        finalText = ""
        sessionState = .idle
        recorderDiagnostic = .init()
        waveformEnergy = []
    }

    func clearResult() {
        discardCurrentDictationSession()
        finalText = ""
        sessionState = .idle
        waveformEnergy = []
    }

    // MARK: - Clipboard

    func copyFinalText() -> Bool {
        let text = finalText.isEmpty ? visibleLiveText : finalText
        guard !text.isEmpty else { return false }
        UIPasteboard.general.string = text
        appendTimeline(.asr, message: L10n.t("timeline.copied"))
        return true
    }

    /// Present the ClipboardBridge handoff page. Called by the URL router
    /// when `mashangxie://dictation/clipboard-start?source=keyboard` is received.
    func presentClipboardHandoff() {
        clipboardHandoffPresentationID = UUID()
        clearResult()
        clipboardHandoffActive = true
        ClipboardBridgeEventLog.shared.record(.init(kind: .deepLinkOpened))
    }

    /// Dismiss the handoff page. Called by the view's onDismiss.
    func dismissClipboardHandoff() {
        clipboardHandoffActive = false
    }

    // MARK: - Credentials

    func reloadCredentials() {
        credentialValues = credentialStore.loadAll()
    }

    func saveCredentials(for provider: LocalCredentialStore.Provider, values: LocalCredentialStore.CredentialValues) throws {
        try credentialStore.save(provider: provider, values: values)
        reloadCredentials()
        appendTimeline(.env, message: L10n.t("timeline.credentials_saved", provider.displayName))
    }

    func clearCredentials(for provider: LocalCredentialStore.Provider) throws {
        try credentialStore.clear(provider: provider)
        reloadCredentials()
        appendTimeline(.env, message: L10n.t("timeline.credentials_cleared", provider.displayName))
    }

    func isProviderConfigured(_ provider: SelectedProvider) -> Bool {
        guard provider.requiresCredentials, let cred = provider.credentialProvider else { return true }
        return credentialStore.isEffectivelyComplete(cred)
    }

    // MARK: - Diagnostics

    func refreshRecorderDiagnostic() {
        guard let recorder else { return }
        recorderDiagnostic.lastDeactivationError = recorder.lastDeactivationError
    }

    func refreshAppleSpeechAuthorization(requestIfNeeded: Bool = false) async {
        let current = Self.currentAppleSpeechAuthorization()
        if requestIfNeeded && current == .notDetermined {
            appleSpeechAuthorization = await Self.requestAppleSpeechAuthorization()
        } else {
            appleSpeechAuthorization = current
        }
    }

    func providerAvailability(for provider: SelectedProvider) -> ProviderAvailability {
        switch provider {
        case .appleSpeech:
            switch appleSpeechAuthorization {
            case .authorized: return .ready
            case .denied: return .permissionDenied
            case .notDetermined: return .permissionNotDetermined
            }
        case .tencent, .aliyun, .volcengine:
            guard let cred = provider.credentialProvider else { return .ready }
            if !credentialStore.isEffectivelyComplete(cred) {
                return .missingCredentials
            }
            return .ready
        }
    }

    // MARK: - Private

    private static func persistProvider(_ provider: SelectedProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
        AppGroup.preferences.set(provider.rawValue, forKey: SharedKeys.provider)
        AppGroup.preferences.synchronize()
    }

    private static func persistLanguage(_ language: SelectedLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
        AppGroup.preferences.set(language.rawValue, forKey: SharedKeys.language)
        AppGroup.preferences.synchronize()
    }

    private static func persistKeyboardDefaults() {
        AppGroup.preferences.set(LayoutType.qwerty.rawValue, forKey: SharedKeys.keyboardLayout)
        AppGroup.preferences.set(DefaultKeyboardLayer.letters.rawValue, forKey: SharedKeys.defaultKeyboardLayer)
        AppGroup.preferences.synchronize()
    }

    private func makeEngine(for provider: SelectedProvider) throws -> ASREngine {
        switch provider {
        case .appleSpeech:
            let adapter = AppleSpeechASREngineAdapter()
            adapter.configure(locale: selectedLanguage.locale)
            return adapter
        case .tencent:
            return try iOSASREngineFactory.makeTencentEngine(store: credentialStore)
        case .aliyun:
            return try iOSASREngineFactory.makeAliyunEngine(store: credentialStore)
        case .volcengine:
            return try iOSASREngineFactory.makeVolcengineEngine(store: credentialStore)
        }
    }

    private func handleStateChange(_ state: MobileDictationState) {
        sessionState = state
        switch state {
        case let .finished(text):
            finalText = text
            appendTimeline(.asr, message: L10n.t("timeline.final_received"))
        case let .failed(message):
            appendTimeline(.asr, message: L10n.t("timeline.failed", message))
        default:
            break
        }
    }

    private func discardCurrentDictationSession() {
        let oldSession = session
        session = nil
        recorder = nil
        oldSession?.onChange = nil
        oldSession?.onPermissionDenied = nil
        oldSession?.cancel()
    }

    private func appendTimeline(_ category: TimelineEvent.Category, message: String) {
        timelineEvents.append(.init(timestamp: Date(), category: category, message: message))
        if timelineEvents.count > 200 {
            timelineEvents.removeFirst(timelineEvents.count - 200)
        }
    }

    private static func currentAppleSpeechAuthorization() -> AppleSpeechAuthorizationStatus {
        mapSpeechAuthorization(SFSpeechRecognizer.authorizationStatus())
    }

    private static func requestAppleSpeechAuthorization() async -> AppleSpeechAuthorizationStatus {
        await withCheckedContinuation { continuation in
            requestSpeechAuthorization { status in
                continuation.resume(returning: mapSpeechAuthorization(status))
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization(
        _ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    private nonisolated static func mapSpeechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) -> AppleSpeechAuthorizationStatus {
        switch status {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

/// 录音器诊断快照，用于 DiagnosticsView 展示。
struct RecorderDiagnostic: Equatable {
    var lastDeactivationError: String?
}

/// Provider 可用性诊断结果。
enum ProviderAvailability: Equatable {
    case ready
    case missingCredentials
    case permissionDenied
    case permissionNotDetermined
    case envLimited(String)

    var displayKey: String {
        switch self {
        case .ready: return "diagnostics.availability.ready"
        case .missingCredentials: return "diagnostics.availability.missing_credentials"
        case .permissionDenied: return "diagnostics.availability.permission_denied"
        case .permissionNotDetermined: return "diagnostics.availability.permission_not_determined"
        case .envLimited: return "diagnostics.availability.env_limited"
        }
    }
}
