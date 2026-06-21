import VoxFlowVoiceCorrection

@MainActor
final class FakeFocusedTextObserver: FocusedTextObserving {
    var captureResult: FocusedTextObservation?
    var recaptureResult: FocusedTextObservation?
    var recaptureResults: [FocusedTextObservation] = []
    private(set) var captureCallCount = 0
    private(set) var recaptureBaselines: [FocusedTextObservation] = []

    func capture() -> FocusedTextObservation? {
        captureCallCount += 1
        return captureResult
    }

    func recapture(matching baseline: FocusedTextObservation) -> FocusedTextObservation? {
        recaptureBaselines.append(baseline)
        if !recaptureResults.isEmpty {
            return recaptureResults.removeFirst()
        }
        return recaptureResult
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
