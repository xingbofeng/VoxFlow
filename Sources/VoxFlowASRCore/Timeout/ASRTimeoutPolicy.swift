import Foundation

public enum ASRTimeoutStage: Equatable, Sendable {
    case preparation
    case firstPartial
    case streamStall
    case final(audioDuration: Duration)
    case workerHeartbeat
    case initialModelCompilation
}

public struct ASRTimeoutPolicy: Equatable, Sendable {
    public static let standard = ASRTimeoutPolicy(
        preparationTimeout: .seconds(60),
        firstPartialTimeout: .seconds(5),
        streamStallTimeout: .seconds(10),
        finalBaseTimeout: .seconds(15),
        finalPerAudioSecondTimeout: .seconds(1),
        workerHeartbeatTimeout: .seconds(5),
        initialModelCompilationTimeout: .seconds(600)
    )

    public let preparationTimeout: Duration
    public let firstPartialTimeout: Duration
    public let streamStallTimeout: Duration
    public let finalBaseTimeout: Duration
    public let finalPerAudioSecondTimeout: Duration
    public let workerHeartbeatTimeout: Duration
    public let initialModelCompilationTimeout: Duration

    public init(
        preparationTimeout: Duration,
        firstPartialTimeout: Duration,
        streamStallTimeout: Duration,
        finalBaseTimeout: Duration,
        finalPerAudioSecondTimeout: Duration,
        workerHeartbeatTimeout: Duration,
        initialModelCompilationTimeout: Duration
    ) {
        self.preparationTimeout = preparationTimeout
        self.firstPartialTimeout = firstPartialTimeout
        self.streamStallTimeout = streamStallTimeout
        self.finalBaseTimeout = finalBaseTimeout
        self.finalPerAudioSecondTimeout = finalPerAudioSecondTimeout
        self.workerHeartbeatTimeout = workerHeartbeatTimeout
        self.initialModelCompilationTimeout = initialModelCompilationTimeout
    }

    public func timeout(for stage: ASRTimeoutStage) -> Duration {
        switch stage {
        case .preparation:
            return preparationTimeout
        case .firstPartial:
            return firstPartialTimeout
        case .streamStall:
            return streamStallTimeout
        case let .final(audioDuration):
            return finalBaseTimeout + Self.scale(
                finalPerAudioSecondTimeout,
                by: Self.ceiledSeconds(in: audioDuration)
            )
        case .workerHeartbeat:
            return workerHeartbeatTimeout
        case .initialModelCompilation:
            return initialModelCompilationTimeout
        }
    }

    private static func ceiledSeconds(in duration: Duration) -> Int64 {
        let components = duration.components
        if components.attoseconds > 0 {
            return components.seconds + 1
        }
        return components.seconds
    }

    private static func scale(_ duration: Duration, by count: Int64) -> Duration {
        guard count > 0 else { return .zero }
        var result: Duration = .zero
        for _ in 0..<count {
            result += duration
        }
        return result
    }
}
