public enum NVIDIANemotronRuntimeRouteStatus: String, Equatable, Sendable {
    case blocked
    case candidate
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
                route: .macOSLocal,
                status: .blocked,
                rationale: "Upstream inference requires NeMo, Python 3.11+, Cython, latest PyTorch, and NVIDIA GPU/CUDA acceleration; no native macOS runtime is confirmed."
            ),
            NVIDIANemotronRuntimeRouteEvaluation(
                route: .externalWorker,
                status: .candidate,
                rationale: "A local or LAN worker can wrap the NeMo cache-aware streaming script while VoxFlow keeps ASRSession semantics in Swift."
            ),
            NVIDIANemotronRuntimeRouteEvaluation(
                route: .remoteService,
                status: .candidate,
                rationale: "A remote service can host NeMo runtime, but it changes the provider privacy boundary and needs explicit user-facing disclosure."
            ),
        ]
    )

    public let routes: [NVIDIANemotronRuntimeRouteEvaluation]

    public init(routes: [NVIDIANemotronRuntimeRouteEvaluation]) {
        self.routes = routes
    }

    public var readyRoute: NVIDIANemotronRuntimeRoute? {
        nil
    }
}
