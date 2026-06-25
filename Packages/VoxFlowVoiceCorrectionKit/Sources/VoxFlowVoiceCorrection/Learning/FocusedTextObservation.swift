public struct FocusedTextObservation: Codable, Sendable, Equatable {
    public let elementIdentity: String
    public let value: String
    public let selectedRange: CorrectionTextRange?
    public let bundleIdentifier: String?
    public let isSecureField: Bool

    public init(
        elementIdentity: String,
        value: String,
        selectedRange: CorrectionTextRange?,
        bundleIdentifier: String?,
        isSecureField: Bool
    ) {
        self.elementIdentity = elementIdentity
        self.value = value
        self.selectedRange = selectedRange
        self.bundleIdentifier = bundleIdentifier
        self.isSecureField = isSecureField
    }
}

@MainActor
public protocol FocusedTextObserving: AnyObject {
    func capture() -> FocusedTextObservation?
    func recapture(matching baseline: FocusedTextObservation) -> FocusedTextObservation?
}

@MainActor
public final class FocusedTextObservationTracker {
    private let observer: any FocusedTextObserving

    public init(observer: any FocusedTextObserving) {
        self.observer = observer
    }

    public func captureBaseline() -> FocusedTextObservation? {
        guard let observation = observer.capture(),
              !observation.isSecureField,
              !observation.value.isEmpty
        else {
            return nil
        }
        return observation
    }

    public func recapture(
        matching baseline: FocusedTextObservation
    ) -> FocusedTextObservation? {
        guard !baseline.isSecureField,
              let observation = observer.recapture(matching: baseline),
              !observation.isSecureField,
              !observation.value.isEmpty,
              observation.elementIdentity == baseline.elementIdentity
        else {
            return nil
        }
        return observation
    }
}

public enum CorrectionObservationPollSchedule {
    public static let defaultOffsets: [Duration] = (1...30).map { .seconds($0) }
}

public protocol CorrectionObservationClock: Sendable {
    func sleep(for duration: Duration) async
}

public struct ContinuousCorrectionObservationClock: CorrectionObservationClock {
    public init() {}

    public func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
