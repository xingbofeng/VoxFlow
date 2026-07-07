import Combine
import Foundation
import Speech
import Shared
import VoxFlowASRRuntime
import VoxFlowAudio

/// Main-app side of the Dictus-style keyboard dictation bridge.
///
/// The keyboard extension never records audio. It writes command flags into the
/// App Group and posts Darwin notifications. This coordinator lives in the main
/// app, owns microphone recording, drives the selected ASR provider, and writes
/// status/results back to the App Group for the keyboard to insert.
@MainActor
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    @Published private(set) var status: DictationStatus = .idle
    @Published private(set) var lastResult: String?
    @Published private(set) var bufferEnergy: [Float] = []
    @Published private(set) var bufferSeconds: Double = 0

    private let store = SharedStatusStore()
    private let defaults = AppGroup.defaultsIfAvailable ?? .standard
    private let credentialStore = LocalCredentialStore()
    private let audioEngine = UnifiedAudioEngine()
    private let asrBridge: DictationASRBridge

    private var latestLiveText = ""
    private var isStopping = false

    var isEngineRunning: Bool {
        audioEngine.isEngineRunning
    }

    private init() {
        self.asrBridge = DictationASRBridge(
            engineBuilder: DefaultProviderEngineBuilder(credentialStore: credentialStore)
        )
        bindAudioEngine()
        observeKeyboardCommands()
        observeAudioInterruptions()
        refreshInitialStatus()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "mashangxie" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let source = components?.queryItems?.first(where: { $0.name == "source" })?.value
        if source == "keyboard" {
            defaults.set(true, forKey: SharedKeys.coldStartActive)
            defaults.set("unknown", forKey: SharedKeys.sourceAppScheme)
            synchronizeDefaults()
        }

        // ClipboardBridge deep link: mashangxie://dictation/clipboard-start
        // Routed by VoxFlowiOSApp.onOpenURL to AppState.presentClipboardHandoff
        // before reaching here. If we do see it, ignore — don't fall through
        // to the AppGroupBridge startFromKeyboardRequest path.
        if url.host == "clipboard-start"
            || (url.host == "dictation" && url.path == "/clipboard-start") {
            return
        }

        guard url.host == "dictate" || url.path == "/dictate" else { return }
        startFromKeyboardRequest()
    }

    func prepareForBackground() {
        // Keep coldStartActive intact here. The keyboard reads it on reappearance to
        // extend the watchdog window while the app is transitioning back out.
        publishCurrentStatus()
    }

    func startDictation() {
        startFromKeyboardRequest()
    }

    func stopDictation() {
        stopRecording()
    }

    func cancelDictation() {
        cancelRecording()
    }

    func resetStatus() {
        if status == .recording || status == .requested || status == .transcribing {
            cancelRecording()
            return
        }

        asrBridge.cancel()
        audioEngine.onAudioFrame = nil
        _ = audioEngine.collectSamples()
        latestLiveText = ""
        lastResult = nil
        isStopping = false
        bufferEnergy = []
        bufferSeconds = 0
        store.clearLiveTranscription()
        defaults.removeObject(forKey: SharedKeys.lastError)
        defaults.removeObject(forKey: SharedKeys.lastTranscription)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.set(0, forKey: SharedKeys.recordingElapsedSeconds)
        writeWaveform([])
        updateStatus(.idle)
    }

    // MARK: - Keyboard commands

    private func bindAudioEngine() {
        audioEngine.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .assign(to: &$bufferEnergy)
        audioEngine.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .assign(to: &$bufferSeconds)
    }

    private func observeAudioInterruptions() {
        NotificationCenter.default.addObserver(
            forName: .audioSessionInterruptedInProcess,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fail("Audio recording was interrupted.")
                DarwinNotificationCenter.post(DarwinNotificationName.audioSessionInterrupted)
            }
        }
    }

    private func observeKeyboardCommands() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            Task { @MainActor in self?.startFromKeyboardRequest() }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.stopRecording) { [weak self] in
            Task { @MainActor in self?.handleStopRequest() }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.cancelRecording) { [weak self] in
            Task { @MainActor in self?.handleCancelRequest() }
        }
    }

    private func startFromKeyboardRequest() {
        guard status == .idle || status == .requested || status == .failed || status == .ready else {
            publishCurrentStatus()
            return
        }

        latestLiveText = ""
        lastResult = nil
        isStopping = false
        bufferEnergy = []
        bufferSeconds = 0
        store.clearLiveTranscription()
        defaults.removeObject(forKey: SharedKeys.lastError)
        defaults.removeObject(forKey: SharedKeys.lastTranscription)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.set(0, forKey: SharedKeys.recordingElapsedSeconds)
        writeWaveform([])
        updateStatus(.requested)

        Task { @MainActor in
            await startRecording()
        }
    }

    private func handleStopRequest() {
        guard store.consumeStopRequested() || status == .recording else { return }
        stopRecording()
    }

    private func handleCancelRequest() {
        _ = store.consumeCancelRequested()
        cancelRecording()
    }

    // MARK: - Recording

    private func startRecording() async {
        guard status == .requested else { return }

        let provider = selectedProvider()
        let language = selectedLanguage()
        let credentialsReady = provider.credentialProvider.map {
            credentialStore.isEffectivelyComplete($0)
        } ?? true
        PersistentLog.log(.diagnosticProbe(
            component: "DictationCoordinator",
            instanceID: "shared",
            action: "startRecording",
            details: "provider=\(provider.rawValue) language=\(language.rawValue) credentialsReady=\(credentialsReady)"
        ))
        if provider == .appleSpeech {
            let authorization = await requestAppleSpeechAuthorizationIfNeeded()
            guard authorization == .authorized else {
                fail("Apple Speech authorization is not available.")
                return
            }
        }

        do {
            try asrBridge.prepare(
                provider: provider,
                language: language,
                onTranscription: { [weak self] text, isFinal in
                    Task { @MainActor in
                        self?.handleTranscription(text: text, isFinal: isFinal)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.fail(error.localizedDescription)
                    }
                }
            )
        } catch {
            PersistentLog.log(.diagnosticProbe(
                component: "DictationCoordinator",
                instanceID: "shared",
                action: "prepareFailed",
                details: "provider=\(provider.rawValue) error=\(error.localizedDescription)"
            ))
            fail(error.localizedDescription)
            return
        }

        do {
            try audioEngine.configureAudioSession()
            let granted = try await audioEngine.ensureMicrophonePermission()
            guard granted else {
                fail("Microphone permission is denied.")
                return
            }

            let bridge = asrBridge
            audioEngine.onAudioFrame = { [bridge] frame in
                bridge.appendAudioFrame(frame)
            }
            try asrBridge.startPrepared()
            try audioEngine.startRecording()
        } catch {
            asrBridge.cancel()
            audioEngine.onAudioFrame = nil
            _ = audioEngine.collectSamples()
            fail(error.localizedDescription)
            return
        }

        updateStatus(.recording)
    }

    private func stopRecording() {
        guard status == .recording || status == .requested else { return }
        isStopping = true
        audioEngine.onAudioFrame = nil
        _ = audioEngine.collectSamples()
        asrBridge.endAudio()
        updateStatus(.transcribing)
    }

    private func cancelRecording() {
        audioEngine.onAudioFrame = nil
        _ = audioEngine.collectSamples()
        asrBridge.cancel()
        latestLiveText = ""
        lastResult = nil
        isStopping = false
        bufferEnergy = []
        bufferSeconds = 0
        store.clearLiveTranscription()
        defaults.removeObject(forKey: SharedKeys.lastError)
        defaults.removeObject(forKey: SharedKeys.lastTranscription)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.set(0, forKey: SharedKeys.recordingElapsedSeconds)
        writeWaveform([])
        updateStatus(.idle)
    }

    private func handleTranscription(text: String, isFinal: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        latestLiveText = text

        if isFinal {
            finish(text)
        } else if status == .transcribing || isStopping {
            store.writeLiveTranscription(text)
            DarwinNotificationCenter.post(DarwinNotificationName.transcriptionPartial)
            updateStatus(.transcribing)
        } else {
            store.writeLiveTranscription(text)
            DarwinNotificationCenter.post(DarwinNotificationName.transcriptionPartial)
            updateStatus(.recording)
        }
    }

    private func finish(_ text: String) {
        audioEngine.onAudioFrame = nil
        _ = audioEngine.collectSamples()
        asrBridge.stop()
        isStopping = false
        lastResult = text
        store.clearLiveTranscription()
        store.writeTranscription(text)
        synchronizeDefaults()
        updateStatus(.ready)
        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
    }

    private func fail(_ message: String) {
        audioEngine.onAudioFrame = nil
        _ = audioEngine.collectSamples()
        asrBridge.cancel()
        isStopping = false
        lastResult = message
        PersistentLog.log(.dictationFailed(error: message))
        store.clearLiveTranscription()
        store.writeError(message)
        synchronizeDefaults()
        updateStatus(.failed)
    }

    private func selectedProvider() -> SelectedProvider {
        let raw = defaults.string(forKey: SharedKeys.provider)
            ?? UserDefaults.standard.string(forKey: "VoxFlowiOS.selectedProvider")
            ?? SelectedProvider.appleSpeech.rawValue
        if raw == "apple" { return .appleSpeech }
        return SelectedProvider(rawValue: raw) ?? .appleSpeech
    }

    private func selectedLanguage() -> SelectedLanguage {
        let raw = defaults.string(forKey: SharedKeys.language)
            ?? UserDefaults.standard.string(forKey: "VoxFlowiOS.selectedLanguage")
            ?? SelectedLanguage.zhCN.rawValue
        if raw == "zh" { return .zhCN }
        return SelectedLanguage(rawValue: raw) ?? .zhCN
    }

    private func requestAppleSpeechAuthorizationIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            Self.requestSpeechAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization(
        _ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    // MARK: - App Group publishing

    private func refreshInitialStatus() {
        status = store.readStatus() ?? .idle
        publishCurrentStatus()
    }

    private func updateStatus(_ next: DictationStatus) {
        status = next
        store.writeStatus(next)
        synchronizeDefaults()
    }

    private func publishCurrentStatus() {
        store.writeStatus(status)
        synchronizeDefaults()
    }

    private func writeWaveform(_ values: [Float]) {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: SharedKeys.waveformEnergy)
        }
    }

    private func synchronizeDefaults() {
        defaults.synchronize()
    }
}
