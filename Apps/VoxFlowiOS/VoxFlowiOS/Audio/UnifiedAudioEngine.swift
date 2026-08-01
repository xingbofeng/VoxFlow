// DictusApp/Audio/UnifiedAudioEngine.swift
// Single audio engine for all recording paths — replaces both AudioRecorder and RawAudioCapture.
// Uses native AVAudioEngine (no WhisperKit dependency). Captured samples are passed to
// transcribe(audioArray:) which accepts any [Float] 16kHz mono array.
import Foundation
@preconcurrency import AVFoundation
import Shared
import VoxFlowAudio

extension Notification.Name {
    /// In-process signal that the AVAudioSession was interrupted or the media
    /// services stack was reset. Consumers (LiveActivityManager, DictationCoordinator)
    /// must treat the audio engine as dead until a successful `warmUp()` returns.
    /// Mirrors the cross-process Darwin notification of the same name (issue #106).
    static let audioSessionInterruptedInProcess = Notification.Name("MashangxieAudioSessionInterrupted")

    /// In-process signal that the warm-state engine was released after the idle
    /// timeout. Consumers should dismiss the Dynamic Island standby indicator —
    /// the next dictation will be a cold start (issue #106 Phase B).
    static let warmStateReleasedInProcess = Notification.Name("MashangxieWarmStateReleased")
}

/// Errors that can occur during audio engine operations.
enum AudioEngineError: Error, LocalizedError {
    case permissionDenied
    case permissionUndetermined
    case phoneCallActive
    case audioHardwareUnavailable
    case installTapFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .permissionUndetermined:
            return "Microphone permission not yet requested"
        case .phoneCallActive:
            return "Micro indisponible pendant un appel"
        case .audioHardwareUnavailable:
            return "Micro indisponible, réessayez dans un instant"
        case .installTapFailed(let reason):
            return "Micro indisponible (\(reason))"
        }
    }
}

private final class AudioSharedDefaultsWriter: @unchecked Sendable {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    func writeHeartbeat(_ timestamp: TimeInterval) {
        defaults?.set(timestamp, forKey: SharedKeys.recordingHeartbeat)
    }

    func writeWaveform(_ values: [Float], elapsedSeconds: Double) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: SharedKeys.waveformEnergy)
        }
        defaults.set(elapsedSeconds, forKey: SharedKeys.recordingElapsedSeconds)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.waveformUpdate)
    }
}

/// Unified audio engine for recording dictation audio.
///
/// WHY this replaces AudioRecorder + RawAudioCapture:
/// Both classes did the same job (capture 16kHz mono Float32 audio). AudioRecorder wrapped
/// WhisperKit's AudioProcessor (tight coupling, manual isEngineRunning bool = bug #38).
/// RawAudioCapture used native AVAudioEngine (zero WhisperKit dependency, computed
/// isEngineRunning = always correct). Since transcribe(audioArray:) accepts any [Float],
/// we don't need WhisperKit's AudioProcessor for capture. One engine, one code path.
///
/// KEY DESIGN: Sample gating via isRecording flag.
/// The engine runs continuously (keeps app alive via UIBackgroundModes:audio) but only
/// accumulates audio samples when isRecording is true. When idle, the engine still processes
/// buffers for heartbeat/energy (background survival) but discards the actual audio data.
/// This eliminates the 64M idle sample accumulation bug (#38).
@MainActor
class UnifiedAudioEngine: ObservableObject {
    // MARK: - Published State

    /// Whether the user is actively recording (samples being accumulated).
    @Published var isRecording = false

    /// Energy levels (0.0-1.0) for waveform visualization.
    @Published var bufferEnergy: [Float] = []

    /// Elapsed recording time in seconds.
    @Published var bufferSeconds: Double = 0

    /// Streaming frame output for Mashangxie ASR providers.
    ///
    /// Upstream Dictus collects a full `[Float]` buffer and transcribes it after
    /// stop. Mashangxie Phase 1 reuses existing realtime `ASREngine`s, so we keep
    /// Dictus capture/waveform/heartbeat behavior and additionally emit each
    /// converted 16kHz mono chunk as a `VoxFlowAudio.AudioFrame`.
    nonisolated(unsafe) var onAudioFrame: (@Sendable (AudioFrame) -> Void)?

    // MARK: - Engine State

    /// Whether the underlying AVAudioEngine is currently running.
    /// COMPUTED from engine.isRunning — always accurate, fixes #38.
    var isEngineRunning: Bool { engine.isRunning }

    /// Whether the engine is in a healthy state for warm-start recording.
    ///
    /// WHY both gates: `engine.isRunning` returns true even after an interruption
    /// began, until we explicitly stop it. `isInterrupted` reflects whether the
    /// AVAudioSession is actually usable. The Live Activity layer queries this to
    /// avoid showing "ready to dictate" while the audio system is dead (issue #106).
    var isHealthy: Bool { engine.isRunning && !isInterrupted }

    /// Current accumulated sample count (for zombie engine health check).
    var currentSampleCount: Int { audioSamples.count }

    // MARK: - Private

    private var engine = AVAudioEngine()

    /// Accumulated audio samples in 16kHz mono Float32 (WhisperKit/Parakeet expected format).
    private var audioSamples: [Float] = []

    /// Converter from hardware sample rate (typically 48kHz) to 16kHz mono.
    /// WHY nonisolated(unsafe): Written once from main thread in startEngine(),
    /// read from audio callback thread in processBuffer(). Write completes before
    /// the audio tap is installed, so no race condition.
    private nonisolated(unsafe) var converter: AVAudioConverter?

    /// App Group defaults cached before the realtime audio callback starts.
    ///
    /// AltStore / free Apple ID signing rewrites bundle identifiers and removes
    /// the original App Group entitlement. In that environment `AppGroup.defaults`
    /// intentionally traps to protect the paid-signing AppGroupBridge contract.
    /// The audio thread must never touch that trapping getter; it only writes
    /// cross-process heartbeat / waveform data when the shared suite is actually
    /// available. ClipboardBridge and the main-app UI do not depend on these
    /// App Group writes.
    private nonisolated(unsafe) let sharedDefaultsWriter = AudioSharedDefaultsWriter(
        defaults: AppGroup.defaultsIfAvailable
    )

    /// Target format: 16kHz mono Float32 — what WhisperKit and Parakeet expect.
    private nonisolated(unsafe) let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Whether the audio session has been configured at least once.
    /// WHY: iOS forbids changing AVAudioSession category from background.
    /// We configure once and keep the category set forever.
    private var sessionConfigured = false

    /// True when an AVAudioSession interruption is currently in flight.
    ///
    /// WHY tracked separately from `engine.isRunning`: When an interruption begins,
    /// iOS deactivates the session under us; the engine may still report `isRunning`
    /// momentarily, but the next `installTap`/`start` will fail. Routing decisions
    /// (Live Activity, transitionToRecording guard) need a fast in-process flag to
    /// know the audio layer is degraded (issue #106).
    private var isInterrupted = false

    /// Re-entry guard for the interruption handler. Prevents a second `.began` /
    /// `.ended` arriving while we're still mutating engine state from a previous
    /// event (Siri → ringing call back-to-back), which would leave a dangling tap.
    private var isHandlingInterruption = false

    /// Generation counter for the underlying AVAudioEngine instance. Bumped on
    /// `handleMediaServicesReset` when we replace the engine. The audio tap closure
    /// captures the generation it was installed under — if a buffer arrives after
    /// the engine has been replaced, the closure bails out instead of writing into
    /// shared `nonisolated(unsafe)` state and racing with the new engine's tap.
    private nonisolated(unsafe) var engineGeneration: UInt64 = 0

    /// Tokens for the AVAudioSession lifecycle observers, retained so we can
    /// remove them in `deinit` and avoid leaking notifications across hot reloads
    /// or future re-instantiation.
    private var notificationObservers: [NSObjectProtocol] = []

    /// Pending idle-release work item (issue #106 Phase B). Armed at the end of
    /// every recording (`collectSamples`) and cancelled at the start of any new
    /// recording or warm-up. If it ever fires, `releaseWarmState()` tears down
    /// the engine + session so the device stops paying for `UIBackgroundModes:audio`.
    private var idleReleaseWorkItem: DispatchWorkItem?

    /// Time at which the most recent recording session ended (`collectSamples`
    /// or `cancelDictation` path). Used to compute how long the engine sat idle
    /// before being released — emitted in the `warmStateReleased(idleSeconds:)`
    /// log event for tuning the timeout.
    private var lastIdleStartTime: Date?

    /// Idle window after which the warm engine + session are released. Hardcoded
    /// for this iteration; a user-facing setting will land as a follow-up
    /// (issue #106 out-of-scope). 10 minutes balances UX (warm starts feel
    /// instant within a normal "back-and-forth dictation session") against
    /// battery drain (3.3%/h baseline drops to ~0%/h after release).
    private let idleReleaseInterval: TimeInterval = 10 * 60

    /// Sample gating flag read from the audio thread.
    /// WHY nonisolated(unsafe): Read from audio callback thread (single reader pattern).
    /// Written from main thread via startRecording()/collectSamples()/stopEngine().
    /// The flag is a simple Bool — partial reads are impossible on ARM64.
    private nonisolated(unsafe) var isRecordingFlag = false

    /// Timestamp of last heartbeat write to App Group.
    /// Throttled to ~1Hz to avoid excessive UserDefaults writes from the audio thread.
    /// WHY nonisolated(unsafe): Written only from the audio callback thread (single writer).
    private nonisolated(unsafe) var lastHeartbeatWrite: TimeInterval = 0

    /// Timestamp of last waveform write to App Group from the audio thread.
    /// Throttled to ~5Hz (every 200ms) — same rate as keyboard waveform display.
    /// WHY from audio thread: In background, iOS throttles DispatchQueue.main.async delivery.
    /// Writing directly from the audio thread bypasses this throttling.
    private nonisolated(unsafe) var lastWaveformWrite: TimeInterval = 0

    /// Timestamp of the last waveform-shape diagnostic emitted from the audio thread.
    private nonisolated(unsafe) var lastWaveformDiagnosticsWrite: TimeInterval = 0

    /// Rolling energy buffer maintained on the audio thread for direct App Group writes.
    /// Separate from @Published bufferEnergy (which is main-thread-only for SwiftUI).
    /// WHY nonisolated(unsafe): Single writer (audio callback thread).
    private nonisolated(unsafe) var audioThreadEnergy: [Float] = []

    /// Rolling per-bucket waveform shape used by the keyboard/App Group snapshot.
    /// Unlike audioThreadEnergy (one RMS value per callback), this keeps a short envelope
    /// history with enough local variation to render an actual waveform silhouette.
    private nonisolated(unsafe) var audioThreadWaveformBins: [Float] = []

    /// Accumulated sample count on the audio thread for elapsed time calculation.
    /// WHY nonisolated(unsafe): Single writer (audio callback thread).
    private nonisolated(unsafe) var audioThreadSampleCount: Int = 0

    /// Sequence number for emitted `AudioFrame`s.
    private nonisolated(unsafe) var audioFrameSequenceNumber: UInt64 = 0

    private let waveformBarCount = 30

    // MARK: - Init / Deinit

    init() {
        registerInterruptionObservers()
    }

    /// Register observers for AVAudioSession lifecycle events that can break the
    /// engine without our knowledge — phone calls, Siri, route loss, media services
    /// reset (issue #106).
    ///
    /// WHY in init (not after first start): Apple delivers the .began interruption
    /// notification immediately when the OS interrupts us, even if we haven't yet
    /// activated the session. Registering early means we never miss one. Observers
    /// are cheap when the session isn't active.
    ///
    /// WHY no `queue: .main` + `Task { @MainActor }` double hop: each Task adds a
    /// runloop tick of latency between AVAudioSession posting the notification and
    /// us mutating `isInterrupted`. Since this class is @MainActor, dispatching
    /// the closure to MainActor.assumeIsolated handles isolation directly.
    private func registerInterruptionObservers() {
        let center = NotificationCenter.default

        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let reasonDescription = note.userInfo?[AVAudioSessionInterruptionReasonKey].flatMap { value -> String in
                if let raw = value as? UInt,
                   let parsed = AVAudioSession.InterruptionReason(rawValue: raw) {
                    return "\(parsed)"
                }
                return "\(value)"
            }
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(
                    typeRaw: typeRaw,
                    reasonDescription: reasonDescription,
                    optionsRaw: optionsRaw
                )
            }
        }

        let routeChangeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let inputs = AVAudioSession.sharedInstance()
                .currentRoute.inputs
                .map { $0.portType.rawValue }
                .joined(separator: ",")
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonRaw: reasonRaw, inputs: inputs)
            }
        }

        let mediaResetToken = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        }

        notificationObservers = [interruptionToken, routeChangeToken, mediaResetToken]
    }

    /// AVAudioSession interruption handler.
    ///
    /// On `.began`: tear down the engine and mark the session unhealthy. The Live
    /// Activity must dismiss because a dead session means the next dictation will
    /// be a cold start, not a warm start (issue #106).
    ///
    /// On `.ended` with `.shouldResume`: try to reactivate and re-warm. If recovery
    /// fails (rare — usually means the OS still holds the audio resource), we leave
    /// the engine cold and accept that the next dictation pays the cold-start cost.
    private func handleInterruption(typeRaw: UInt?, reasonDescription: String?, optionsRaw: UInt?) {
        // Re-entry guard: a second interruption arriving before we finish handling
        // the previous one (Siri → ringing call back-to-back) would leave a dangling
        // tap. The MainActor isolation already serialises calls, so the flag only
        // needs to cover async work inside this method (warmUp on .ended).
        guard !isHandlingInterruption else {
            PersistentLog.log(.engineWarmUpFailed(
                context: "interruption",
                error: "reentrant interruption ignored"
            ))
            return
        }
        isHandlingInterruption = true
        defer { isHandlingInterruption = false }

        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .began:
            let reason = reasonDescription ?? "unknown"

            isInterrupted = true
            isRecording = false
            isRecordingFlag = false
            cancelIdleRelease()

            // Stop the engine so the next start() reinstalls the tap with a fresh
            // hardware format. Don't deactivate the session — iOS will do that for us
            // and re-asks ownership when the interruption ends.
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()

            PersistentLog.log(.audioInterruptionBegan(reason: reason))

            // Notify in-process listeners (LiveActivityManager, DictationCoordinator)
            // immediately. Darwin notification mirrors for cross-process consumers
            // (keyboard ext) so they can stop trusting the warm-state contract.
            NotificationCenter.default.post(name: .audioSessionInterruptedInProcess, object: nil)
            DarwinNotificationCenter.post(DarwinNotificationName.audioSessionInterrupted)

        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            let shouldResume = options.contains(.shouldResume)

            // We deliberately do NOT auto-resume here even when shouldResume is true.
            //
            // WHY: the user just finished a phone call (or whatever interruption);
            // they have not asked to dictate. Eagerly re-warming the engine
            // re-activates AVAudioSession, which iOS surfaces as the orange mic
            // indicator in its Dynamic Island — but our Live Activity is already
            // dismissed (Phase A correctly tears it down on .began). The combination
            // is the worst of both: audio resources held + no Dictus UX visible.
            //
            // Instead, leave the engine cold and rely on the natural re-warm paths:
            //  - if user reopens the app, DictationCoordinator's didBecomeActive
            //    observer calls warmUp.
            //  - if user taps the keyboard mic, the cold-start dictation path
            //    starts the engine fresh.
            // Either way, the warm-state contract matches reality and the orange
            // mic only appears when the user actually wants to record (issue #106).
            PersistentLog.log(.audioInterruptionEnded(shouldResume: shouldResume, restored: false))

        @unknown default:
            return
        }
    }

    /// Audio route change handler. Logs only — most route changes (headphones
    /// plugged/unplugged) are handled transparently by AVAudioEngine. We do NOT
    /// tear down the engine here; that path is reserved for explicit interruptions.
    /// If the input route disappears entirely, the next recording attempt fails
    /// gracefully via the hwFormat guards in `startEngine()`.
    private func handleRouteChange(reasonRaw: UInt?, inputs: String) {
        guard let raw = reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else {
            return
        }

        PersistentLog.log(.audioRouteChanged(
            reason: "\(reason)",
            details: "inputs=\(inputs.isEmpty ? "none" : inputs)"
        ))
    }

    /// AVAudioSession.mediaServicesWereReset handler. This is rare but brutal:
    /// the entire audio stack is reset by the OS and ALL existing AVAudioEngine
    /// instances are invalid. We must allocate a fresh engine and reconfigure
    /// before any future start() call.
    private func handleMediaServicesReset() {
        PersistentLog.log(.audioMediaServicesReset)

        cancelIdleRelease()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Bump generation BEFORE replacing the engine so any in-flight tap callbacks
        // from the old engine see a stale generation and bail out instead of writing
        // into shared audio-thread state and racing with the new engine's tap.
        engineGeneration &+= 1
        engine = AVAudioEngine()
        converter = nil
        sessionConfigured = false
        isInterrupted = true
        isRecording = false
        isRecordingFlag = false

        NotificationCenter.default.post(name: .audioSessionInterruptedInProcess, object: nil)
        DarwinNotificationCenter.post(DarwinNotificationName.audioSessionInterrupted)
    }

    // MARK: - Session & Permissions (ported from AudioRecorder)

    /// Configure the audio session. Must be called from foreground.
    ///
    /// WHY .allowBluetoothA2DP (not .allowBluetooth) — fix #85:
    /// .allowBluetooth enables HFP (Hands-Free Profile) which hijacks AirPods AVRCP
    /// controls — single-tap play/pause stops working for Music app during recording.
    /// .allowBluetoothA2DP keeps A2DP output on AirPods without activating HFP:
    /// built-in mic is used for recording, AirPods controls stay with media apps.
    /// Confirmed via WhisperFlow reverse-engineering (same NoBluetooth approach).
    ///
    /// WHY .duckOthers:
    /// Automatically lowers other apps' volume (~60%) while Dictus's engine is active.
    /// The AirPods hijack was caused by HFP (.allowBluetooth), not ducking.
    ///
    /// WHY .defaultToSpeaker:
    /// Without it, .playAndRecord routes output to the earpiece by default — nearly
    /// inaudible without headphones. .defaultToSpeaker sends audio to the loudspeaker.
    ///
    /// WHY setActive every time (no sessionConfigured guard for setActive):
    /// iOS interrupts the audio session when the app goes to background. Even if the
    /// category was set, setActive(true) must be called again on foreground return.
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            try session.setCategory(.playAndRecord, options: [.allowBluetoothA2DP, .defaultToSpeaker, .duckOthers])
        }
        try session.setActive(true)
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        sessionConfigured = true

        PersistentLog.log(.audioSessionConfigured(category: "playAndRecord"))
    }

    /// Check and request microphone permission if needed.
    /// Returns true if permission is granted, false otherwise.
    func ensureMicrophonePermission() async throws -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            return granted
        case .denied:
            throw AudioEngineError.permissionDenied
        @unknown default:
            return false
        }
    }

    // MARK: - Engine Lifecycle

    /// Start the engine in idle mode (running but not recording).
    /// Keeps the app alive in background via UIBackgroundModes:audio.
    func warmUp() throws {
        // Cancel any pending idle release — we're explicitly going back warm.
        cancelIdleRelease()

        guard !engine.isRunning else {
            PersistentLog.log(.engineWarmUpSuccess(context: "already running"))
            return
        }
        try startEngine()
        PersistentLog.log(.engineWarmUpSuccess(context: "unifiedEngine-warmUp"))
    }

    /// Begin recording: purge idle audio and start accumulating samples.
    /// If the engine isn't running yet, starts it first (<100ms).
    func startRecording() throws {
        // Cancel any pending idle release — recording activity resets the timer.
        cancelIdleRelease()

        if !engine.isRunning {
            try startEngine()
        }
        purgeState()
        isRecording = true
        isRecordingFlag = true
        PersistentLog.log(.audioEngineStarted)
    }

    /// Collect recorded samples WITHOUT stopping the engine.
    /// Keeps the engine alive for subsequent recordings (no cold start needed).
    ///
    /// WHY keep engine running: iOS requires an active audio engine to keep
    /// the app alive in background (UIBackgroundModes:audio). Stopping the engine
    /// causes iOS to suspend the app, breaking Darwin notification reception.
    ///
    /// - Returns: Audio samples ready for transcription. Engine keeps running.
    func collectSamples() -> [Float] {
        isRecording = false
        isRecordingFlag = false

        let samples = audioSamples
        audioSamples = []

        PersistentLog.log(.engineCollectResult(sampleCount: samples.count, engineRunning: engine.isRunning))

        if #available(iOS 14.0, *) {
            AppLogger.app.info("UnifiedAudioEngine collectSamples. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", Double(samples.count) / 16000.0), privacy: .public)s, engine still running")
        }

        // Reset published state but keep engine running
        bufferEnergy = []
        bufferSeconds = 0

        // Arm the idle-release timer (issue #106 Phase B). If the user starts a
        // new recording or warms up before the timer fires, it gets cancelled.
        scheduleIdleRelease()

        return samples
    }

    /// Stop the engine completely and return all accumulated samples.
    /// After this, the next recording requires warmUp() or startRecording().
    ///
    /// - Returns: Audio samples ready for transcription.
    func stopEngine() -> [Float] {
        cancelIdleRelease()
        isRecording = false
        isRecordingFlag = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let samples = audioSamples
        audioSamples = []

        if #available(iOS 14.0, *) {
            AppLogger.app.info("UnifiedAudioEngine stopped. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", Double(samples.count) / 16000.0), privacy: .public)s")
        }

        bufferEnergy = []
        bufferSeconds = 0

        return samples
    }

    /// Fully deactivate audio: stop engine + deactivate AVAudioSession.
    /// Call when user explicitly stops all audio (e.g., Power button in Dynamic Island).
    func deactivateSession() {
        cancelIdleRelease()
        isRecording = false
        isRecordingFlag = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioSamples = []
        PersistentLog.log(.audioEngineStopped)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionConfigured = false

        bufferEnergy = []
        bufferSeconds = 0
    }

    /// Force restart the engine (stop + removeTap + reconfigure + start).
    /// Used to recover from zombie engine state where isRunning == true but tap receives no buffers.
    func forceRestart() {
        cancelIdleRelease()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sessionConfigured = false
        PersistentLog.log(.audioEngineStopped)

        do {
            try configureAudioSession()
            try startEngine()
            PersistentLog.log(.engineWarmUpSuccess(context: "forceRestart"))
        } catch {
            PersistentLog.log(.engineWarmUpFailed(context: "forceRestart", error: error.localizedDescription))
        }
    }

    // MARK: - Idle Release (issue #106 Phase B)

    /// Arm the idle-release work item. Idempotent: cancels any prior timer first.
    /// The work runs on the main queue after `idleReleaseInterval` elapses with
    /// no recording activity. Must be called from MainActor context.
    private func scheduleIdleRelease() {
        cancelIdleRelease()
        lastIdleStartTime = Date()

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.releaseWarmState(reason: "idleTimeout")
            }
        }
        idleReleaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleReleaseInterval, execute: work)
    }

    /// Cancel a pending idle release. Safe to call when none is armed.
    private func cancelIdleRelease() {
        idleReleaseWorkItem?.cancel()
        idleReleaseWorkItem = nil
    }

    /// Wall-clock backstop for the asyncAfter timer. If iOS suspended the main
    /// queue while we were backgrounded, `scheduleIdleRelease`'s `asyncAfter`
    /// can fire late or get coalesced. The DictationCoordinator's
    /// `didBecomeActive` handler calls this to verify: if we have been idle
    /// past the threshold without the timer firing, release now (the engine is
    /// burning battery for nothing). Issue #106 Phase B.
    func enforceIdleReleaseIfDue() {
        guard let started = lastIdleStartTime else { return }
        let idle = Date().timeIntervalSince(started)
        guard idle >= idleReleaseInterval else { return }
        releaseWarmState(reason: "wallClockBackstop")
    }

    /// Tear down the warm-state engine and deactivate the AVAudioSession.
    ///
    /// Called by the idle timer (`scheduleIdleRelease`). Public so the
    /// scenePhase.active path can call it explicitly if needed (currently
    /// unused — re-warm goes through `warmUp` which trumps the timer). After
    /// release, the next dictation will pay the cold-start cost (~100ms engine
    /// boot + cached WhisperKit init).
    ///
    /// Posts both an in-process notification (Live Activity dismisses) and a
    /// Darwin notification (cross-process consumers can react). Issue #106.
    func releaseWarmState(reason: String) {
        // No-op if already released. Prevents double-deactivation logs and
        // redundant Darwin posts when called from multiple paths.
        guard engine.isRunning || sessionConfigured else { return }

        let idleSeconds: Int = {
            guard let started = lastIdleStartTime else { return 0 }
            return Int(Date().timeIntervalSince(started))
        }()

        isRecording = false
        isRecordingFlag = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Bump generation so any in-flight tap callback bails out before mutating
        // shared audio-thread state (matches the mediaServicesWereReset pattern).
        engineGeneration &+= 1

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        sessionConfigured = false
        converter = nil
        lastIdleStartTime = nil
        idleReleaseWorkItem = nil

        PersistentLog.log(.warmStateReleased(idleSeconds: idleSeconds))
        if #available(iOS 14.0, *) {
            AppLogger.app.info("Warm state released after \(idleSeconds, privacy: .public)s idle (reason: \(reason, privacy: .public))")
        }

        NotificationCenter.default.post(name: .warmStateReleasedInProcess, object: nil)
    }

    // MARK: - Private Helpers

    /// Start the AVAudioEngine with a tap on the input node.
    private func startEngine() throws {
        audioSamples = []
        audioThreadEnergy = []
        audioThreadWaveformBins = []
        audioThreadSampleCount = 0
        audioFrameSequenceNumber = 0
        lastHeartbeatWrite = 0
        lastWaveformWrite = 0
        lastWaveformDiagnosticsWrite = 0

        let inputNode = engine.inputNode
        var hwFormat = inputNode.outputFormat(forBus: 0)

        // Guard: zero-channel format means hardware is unavailable (phone call active)
        guard hwFormat.channelCount > 0 else {
            throw AudioEngineError.phoneCallActive
        }

        // B.2 — One-shot retry when hardware reports a valid channel count but
        // sampleRate == 0. Seen on wake-from-URL-scheme: setActive(true) returns
        // success but the input node hasn't finished negotiating the format.
        // installTap throws `IsFormatSampleRateAndChannelCountValid` NSException
        // in that window, causing SIGABRT (#102).
        if hwFormat.sampleRate == 0 {
            usleep(50_000)
            hwFormat = inputNode.outputFormat(forBus: 0)
        }

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            PersistentLog.log(.dictationFailed(
                error: "invalid hwFormat: sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount)"
            ))
            throw AudioEngineError.audioHardwareUnavailable
        }

        // Guard: detect telephony audio route (phone call in progress)
        // WHY only check inputs for "telephony" (not builtInReceiver on outputs):
        // Without .defaultToSpeaker, iOS routes output to builtInReceiver by default.
        // That's normal operation, not a phone call indicator.
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        let hasTelephony = currentRoute.inputs.contains {
            $0.portType.rawValue.lowercased().contains("telephony")
        }
        if hasTelephony {
            throw AudioEngineError.phoneCallActive
        }

        // Create converter from hardware format to 16kHz mono
        guard let conv = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw NSError(domain: "UnifiedAudioEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter from \(hwFormat) to 16kHz mono"])
        }
        converter = conv

        // Remove any stale tap before installing a new one.
        // WHY: If a previous startEngine() installed a tap but engine.start() threw
        // (e.g., app in background → AUIOClient_StartIO error), the tap remains
        // but the engine isn't running. The next call crashes on installTap.
        inputNode.removeTap(onBus: 0)

        // Wrap installTap in an Objective-C @try/@catch. AVFoundation raises an
        // NSException (uncatchable in Swift) when the format is invalid in ways
        // our pre-flight guards don't cover (#71, #102). Without this shim the
        // process aborts with SIGABRT. Swift imports the Objective-C
        // `tryBlock:error:` as a throwing method.
        // Capture the engine generation at install time. Buffers arriving after a
        // mediaServicesWereReset has bumped the generation (and replaced the engine)
        // belong to the dead engine and must be discarded — otherwise they race
        // with the new engine's tap on shared `nonisolated(unsafe)` audio-thread
        // state (issue #106 review).
        let installedGeneration = engineGeneration
        let tapBlock = Self.makeTapBlock(owner: self, installedGeneration: installedGeneration)
        do {
            try ObjCExceptionCatcher.catchException {
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat, block: tapBlock)
            }
        } catch {
            let reason = (error as NSError).localizedDescription
            PersistentLog.log(.dictationFailed(error: "installTap NSException: \(reason)"))
            throw AudioEngineError.installTapFailed(reason)
        }

        // engine.start() can throw both Swift errors (AUIOClient_StartIO) and
        // Objective-C NSExceptions. Wrap in both ObjCExceptionCatcher AND Swift do/catch.
        var swiftStartError: Error?
        do {
            try ObjCExceptionCatcher.catchException {
                do {
                    try self.engine.start()
                } catch {
                    swiftStartError = error
                }
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            let reason = (error as NSError).localizedDescription
            PersistentLog.log(.dictationFailed(error: "engine.start NSException: \(reason)"))
            throw AudioEngineError.installTapFailed(reason)
        }
        if let swiftStartError {
            inputNode.removeTap(onBus: 0)
            throw swiftStartError
        }

        // Engine is healthy again — clear any interruption flag set by a previous
        // .began handler. Centralising the clear here means every successful start
        // path (warmUp, startRecording, didBecomeActive recovery, forceRestart,
        // .ended interruption resume) ends up healthy without each caller having
        // to remember to flip the flag.
        isInterrupted = false

        if #available(iOS 14.0, *) {
            AppLogger.app.info("UnifiedAudioEngine started (hw: \(hwFormat.sampleRate, privacy: .public)Hz -> 16kHz)")
        }
    }

    /// Create the AVAudioEngine tap block outside MainActor isolation.
    ///
    /// Swift 6 checks the executor of closures created in a `@MainActor` method.
    /// AVAudioEngine invokes this block on its realtime audio queue, so the block
    /// must be formed from a nonisolated context and call only nonisolated state.
    private nonisolated static func makeTapBlock(
        owner: UnifiedAudioEngine,
        installedGeneration: UInt64
    ) -> AVAudioNodeTapBlock {
        { [weak owner] buffer, _ in
            guard let owner else { return }
            guard installedGeneration == owner.engineGeneration else { return }
            owner.processBuffer(buffer)
        }
    }

    /// Reset recording state without stopping the engine.
    private func purgeState() {
        audioSamples = []
        bufferEnergy = []
        bufferSeconds = 0
        audioThreadEnergy = []
        audioThreadWaveformBins = []
        audioThreadSampleCount = 0
        audioFrameSequenceNumber = 0
        lastWaveformWrite = 0
        lastWaveformDiagnosticsWrite = 0
    }

    /// Process incoming audio buffer: convert to 16kHz and compute energy for waveform.
    ///
    /// WHY nonisolated: This callback fires on the audio thread. We do the CPU-intensive
    /// conversion here, then dispatch UI updates and sample accumulation to main thread.
    ///
    /// SAMPLE GATING: Samples only accumulate when isRecordingFlag is true. When idle,
    /// the engine still processes buffers for heartbeat + waveform (keeps background alive)
    /// but discards audio data. This prevents the 64M idle sample accumulation bug (#38).
    ///
    /// IDLE FAST PATH (issue #106 Phase C): When `isRecordingFlag` is false, we skip the
    /// converter, waveform compute, energy buffer maintenance, and the main-thread
    /// dispatch — none of those outputs are consumed when no one is dictating. We only
    /// emit a sparse heartbeat (every 3s instead of 1s) so the keyboard's watchdog
    /// can still see the app is alive when a future dictation starts.
    ///
    /// WHY 3s (not 10s): `isRecordingFlag` is false during `.transcribing` too —
    /// `collectSamples()` flips it to false before transcription begins. The keyboard
    /// watchdog falls back to the heartbeat with a 5s threshold during active dictation.
    /// A 10s throttle let transcriptions longer than 5s falsely trip the watchdog.
    /// 3s keeps us safely below the threshold; the per-buffer drain reduction comes
    /// from skipping conversion + waveform compute, not from the heartbeat cadence.
    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let now = Date().timeIntervalSince1970

        // Idle fast path — sparse heartbeat only.
        if !isRecordingFlag {
            let idleHeartbeatThrottle: TimeInterval = 3.0
            if now - lastHeartbeatWrite >= idleHeartbeatThrottle {
                lastHeartbeatWrite = now
                sharedDefaultsWriter.writeHeartbeat(now)
            }
            return
        }

        guard let converter else { return }

        // Calculate output frame count: input frames * (target rate / source rate) + 1
        let ratio = 16000.0 / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        // Convert from hardware format to 16kHz mono
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            if #available(iOS 14.0, *) {
                AppLogger.app.warning("Audio conversion error: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        // Extract Float32 samples from the converted buffer
        guard let channelData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        let frameStartSample = UInt64(audioThreadSampleCount)
        let frameSequence = audioFrameSequenceNumber
        audioFrameSequenceNumber &+= 1

        if let onAudioFrame {
            let frame = AudioFrame(
                sequenceNumber: frameSequence,
                startSample: frameStartSample,
                samples: ContiguousArray(samples),
                sampleRate: 16_000,
                capturedAt: ContinuousClock().now
            )
            onAudioFrame(frame)
        }

        // Compute RMS energy for this buffer (0.0-1.0 range)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        // Scale RMS to waveform range. 15x scaling maps: quiet speech (0.01) → 0.15,
        // normal (0.05) → 0.75, loud (0.07+) → 1.0 capped.
        let energy = min(rms * 15.0, 1.0)

        // === Audio thread writes (bypass main thread throttling in background) ===

        // Update audio-thread energy buffer (rolling window of last 30 values)
        audioThreadEnergy.append(energy)
        if audioThreadEnergy.count > 30 {
            audioThreadEnergy.removeFirst(audioThreadEnergy.count - 30)
        }

        // Build a short-lived waveform silhouette from local buckets inside the current buffer.
        // WHY: A single RMS value per callback tends to produce a flat line that only moves
        // vertically. Splitting the converted buffer into several peak+RMS buckets preserves
        // intra-utterance shape, which makes the keyboard waveform feel alive even after app
        // switches or when speech loudness is relatively stable.
        let waveformBuckets = makeWaveformBuckets(from: samples)
        audioThreadWaveformBins.append(contentsOf: waveformBuckets)
        if audioThreadWaveformBins.count > waveformBarCount {
            audioThreadWaveformBins.removeFirst(audioThreadWaveformBins.count - waveformBarCount)
        }

        // Write heartbeat (~1Hz) during recording
        if now - lastHeartbeatWrite >= 1.0 {
            lastHeartbeatWrite = now
            sharedDefaultsWriter.writeHeartbeat(now)
        }

        // Write waveform data + elapsed time to App Group (~5Hz)
        if now - lastWaveformWrite >= 0.2 {
            lastWaveformWrite = now
            audioThreadSampleCount += 0 // count is updated in main thread dispatch below
            let snapshot = makeWaveformSnapshot()
            sharedDefaultsWriter.writeWaveform(
                snapshot,
                elapsedSeconds: Double(audioThreadSampleCount) / 16000.0
            )

            if now - lastWaveformDiagnosticsWrite >= 1.0 {
                lastWaveformDiagnosticsWrite = now
                PersistentLog.log(.diagnosticProbe(
                    component: "UnifiedAudioEngine",
                    instanceID: "shared",
                    action: "waveformSnapshot",
                    details: waveformStatsDetails(snapshot)
                ))
            }
        }

        // Track sample count on audio thread (needed for elapsed time in App Group writes)
        audioThreadSampleCount += samples.count

        // === Main thread dispatch (for in-app UI: RecordingView, SwiftUI) ===

        let uiSamples = samples
        Task { @MainActor [weak self] in
            guard let self else { return }
            // SAMPLE GATE: only accumulate when recording
            guard self.isRecording else { return }
            self.audioSamples.append(contentsOf: uiSamples)
            self.bufferSeconds = Double(self.audioSamples.count) / 16000.0

            // Maintain a rolling window of energy values (last 30 = matches barCount in BrandWaveform)
            self.bufferEnergy = self.makeWaveformSnapshot()
        }
    }

    private nonisolated func makeWaveformBuckets(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }

        let bucketCount = max(3, min(6, samples.count / 160))
        let bucketSize = max(samples.count / bucketCount, 1)
        var buckets: [Float] = []
        buckets.reserveCapacity(bucketCount)

        var start = 0
        while start < samples.count {
            let end = min(start + bucketSize, samples.count)
            let slice = samples[start..<end]

            var sumSquares: Float = 0
            var peak: Float = 0
            for sample in slice {
                let magnitude = abs(sample)
                sumSquares += magnitude * magnitude
                peak = max(peak, magnitude)
            }

            let rms = sqrt(sumSquares / Float(max(slice.count, 1)))
            let shaped = min(max((peak * 0.65) + (rms * 6.5), 0), 1)
            buckets.append(shaped)
            start = end
        }

        return buckets
    }

    private nonisolated func makeWaveformSnapshot() -> [Float] {
        let source = audioThreadWaveformBins.isEmpty ? audioThreadEnergy : audioThreadWaveformBins
        let resampled = resampleWaveform(source, targetCount: waveformBarCount)
        return enhanceWaveformContrast(resampled)
    }

    private nonisolated func resampleWaveform(_ source: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0 else { return [] }
        guard !source.isEmpty else { return Array(repeating: 0, count: targetCount) }
        guard source.count != targetCount else { return source }

        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let position = Float(index) / Float(max(targetCount - 1, 1))
            let arrayIndex = position * Float(source.count - 1)
            let lower = Int(arrayIndex)
            let upper = min(lower + 1, source.count - 1)
            let fraction = arrayIndex - Float(lower)
            let value = source[lower] * (1 - fraction) + source[upper] * fraction
            result.append(min(max(value, 0), 1))
        }

        return result
    }

    private nonisolated func enhanceWaveformContrast(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue

        guard maxValue > 0.06 else { return values }

        if spread < 0.12 {
            let centerBias = stride(from: 0, to: values.count, by: 1).map { index -> Float in
                let normalized = Float(index) / Float(max(values.count - 1, 1))
                let distance = abs(normalized - 0.5)
                return 1.0 - (distance * 0.18)
            }

            return values.enumerated().map { index, value in
                let normalized: Float
                if spread > 0.0001 {
                    normalized = (value - minValue) / spread
                } else {
                    normalized = 0.5
                }

                let floor = min(maxValue * 0.28, 0.16)
                let stretched = floor + normalized * (1 - floor)
                return min(max(stretched * centerBias[index], 0), 1)
            }
        }

        return values
    }

    private nonisolated func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }
}
