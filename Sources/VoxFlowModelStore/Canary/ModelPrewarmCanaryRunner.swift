import Foundation

public struct ModelCanaryAudio: Equatable, Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public let expectedTokens: [String]

    public init(
        samples: [Float],
        sampleRate: Int,
        expectedTokens: [String]
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.expectedTokens = expectedTokens
    }

    public var durationSeconds: Double {
        guard sampleRate > 0 else {
            return 0
        }
        return Double(samples.count) / Double(sampleRate)
    }
}

public struct ModelPrewarmMetrics: Equatable, Sendable {
    public let loadTime: Duration
    public let canaryRTF: Double

    public init(loadTime: Duration, canaryRTF: Double) {
        self.loadTime = loadTime
        self.canaryRTF = canaryRTF
    }
}

public struct ModelPrewarmReport: Equatable, Sendable {
    public let transcript: String
    public let metrics: ModelPrewarmMetrics

    public init(transcript: String, metrics: ModelPrewarmMetrics) {
        self.transcript = transcript
        self.metrics = metrics
    }

    public var isReady: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ModelPrewarmError: Error, Equatable, Sendable {
    case emptyCanaryOutput
    case missingExpectedToken(String)
}

public protocol ModelRuntimePreparing: Sendable {
    func load(installation: ModelInstallation) async throws
    func compile(installation: ModelInstallation) async throws
    func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String
}

public struct ModelPrewarmCanaryRunner: Sendable {
    public init() {}

    public func prepare(
        installation: ModelInstallation,
        canaryAudio: ModelCanaryAudio,
        runtime: any ModelRuntimePreparing
    ) async throws -> ModelPrewarmReport {
        let clock = ContinuousClock()

        let loadStart = clock.now
        try await runtime.load(installation: installation)
        let loadTime = loadStart.duration(to: clock.now)

        try await runtime.compile(installation: installation)

        let canaryStart = clock.now
        let transcript = try await runtime.transcribeCanary(
            installation: installation,
            audio: canaryAudio
        )
        let canaryElapsed = canaryStart.duration(to: clock.now)

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canaryAudio.expectedTokens.isEmpty || !trimmed.isEmpty else {
            throw ModelPrewarmError.emptyCanaryOutput
        }

        for token in canaryAudio.expectedTokens where !transcript.contains(token) {
            throw ModelPrewarmError.missingExpectedToken(token)
        }

        return ModelPrewarmReport(
            transcript: transcript,
            metrics: ModelPrewarmMetrics(
                loadTime: loadTime,
                canaryRTF: canaryRTF(elapsed: canaryElapsed, audio: canaryAudio)
            )
        )
    }

    private func canaryRTF(elapsed: Duration, audio: ModelCanaryAudio) -> Double {
        guard audio.durationSeconds > 0 else {
            return 0
        }
        return elapsed.secondsValue / audio.durationSeconds
    }
}

private extension Duration {
    var secondsValue: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
