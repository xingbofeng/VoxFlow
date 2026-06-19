public enum NVIDIANemotronRuntimeRouteStatus: String, Equatable, Sendable {
    case blocked
    case candidate
    case ready
}

public struct NVIDIANemotronRuntimeRouteEvaluation: Equatable, Sendable {
    public let route: NVIDIANemotronRuntimeRoute
    public let status: NVIDIANemotronRuntimeRouteStatus
    public let rationale: String

    public init(
        route: NVIDIANemotronRuntimeRoute,
        status: NVIDIANemotronRuntimeRouteStatus,
        rationale: String
    ) {
        self.route = route
        self.status = status
        self.rationale = rationale
    }
}

public struct NVIDIANemotronRuntimeAssessment: Equatable, Sendable {
    public static let current = NVIDIANemotronRuntimeAssessment(
        routes: [
            NVIDIANemotronRuntimeRouteEvaluation(
                route: .speechSwiftCoreML,
                status: .ready,
                rationale: "speech-swift provides a native CoreML NemotronStreamingASR runtime with incremental partial and final transcripts."
            ),
        ]
    )

    public let routes: [NVIDIANemotronRuntimeRouteEvaluation]

    public init(routes: [NVIDIANemotronRuntimeRouteEvaluation]) {
        self.routes = routes
    }

    public var readyRoute: NVIDIANemotronRuntimeRoute? {
        routes.first { $0.status == .ready }?.route
    }
}
