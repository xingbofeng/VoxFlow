import VoxFlowVoiceCorrection

@MainActor
final class FakeFocusedTextObserver: FocusedTextObserving {
    var captureResult: FocusedTextObservation?
    var captureResults: [FocusedTextObservation?] = []
    var recaptureResult: FocusedTextObservation?
    var recaptureResults: [FocusedTextObservation] = []
    var onRecapture: (() -> Void)?
    private(set) var captureCallCount = 0
    private(set) var recaptureBaselines: [FocusedTextObservation] = []

    func capture() -> FocusedTextObservation? {
        captureCallCount += 1
        if !captureResults.isEmpty {
            return captureResults.removeFirst()
        }
        return captureResult
    }

    func recapture(matching baseline: FocusedTextObservation) -> FocusedTextObservation? {
        recaptureBaselines.append(baseline)
        let observation: FocusedTextObservation?
        if !recaptureResults.isEmpty {
            observation = recaptureResults.removeFirst()
        } else {
            observation = recaptureResult
        }
        onRecapture?()
        return observation
    }
}

actor FakeCorrectionObservationClock: CorrectionObservationClock {
    private(set) var sleeps: [Duration] = []

    func sleep(for duration: Duration) async {
        sleeps.append(duration)
    }

    func recordedSleeps() -> [Duration] {
        sleeps
    }
}
