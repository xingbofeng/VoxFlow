import Foundation
import RimeKitObjC

public enum NativeChineseRimeBridgeError: Error, Equatable {
    case deploymentFailed
    case sessionUnavailable
    case schemaSelectionFailed(String)
    case inputRejected(String)
}

@MainActor
public final class NativeChineseRimeBridge: ChineseRimeBridge {
    public private(set) var state: ChineseCompositionState
    public private(set) var status: ChineseInputStatus = .idle

    private static let lifecycleLock = NSLock()
    private static var didSetup = false
    private static var didInitializeAndDeploy = false

    private let api = IRimeAPI()
    private let directories: RimeDataDirectories?
    private let resourceBundle: Bundle?
    private let fileManager: FileManager
    private var mode: ChineseInputMode
    private var session: RimeSessionId = 0
    private var didStart = false

    public init(
        mode: ChineseInputMode = .chineseQwerty,
        directories: RimeDataDirectories? = nil,
        bundle: Bundle? = nil,
        fileManager: FileManager = .default
    ) {
        self.mode = mode
        self.directories = directories
        self.resourceBundle = bundle
        self.fileManager = fileManager
        self.state = .init()
    }

    deinit {
        if session != 0 {
            _ = api.destroySession(session)
        }
    }

    public func start(hasFullAccess: Bool) async throws {
        status = .starting
        let dataDirectories = directories ?? Self.defaultDirectories()
        let plan = RimeSchemaDeploymentPlan(
            directories: dataDirectories,
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        let useAppGroup = hasFullAccess && fileManager.fileExists(atPath: dataDirectories.appGroupRoot.path)
        let sharedSupport = useAppGroup ? dataDirectories.appGroupSharedSupport : dataDirectories.sandboxSharedSupport
        let userData = useAppGroup ? dataDirectories.appGroupUserData : dataDirectories.sandboxUserData
        try plan.deployBuiltInSchemas(
            from: resourceBundle ?? Self.defaultResourceBundle(),
            sharedSupportDirectory: sharedSupport,
            userDataDirectory: userData,
            fileManager: fileManager
        )

        let logs = userData.appendingPathComponent("Logs", isDirectory: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)

        let traits = IRimeTraits()
        traits.sharedDataDir = sharedSupport.path
        traits.userDataDir = userData.path
        traits.distributionName = "Mashangxie"
        traits.distributionCodeName = "Mashangxie"
        traits.distributionVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        traits.appName = "rime.Mashangxie"
        traits.logDir = logs.path
        traits.minLogLevel = 2

        try Self.setupAndDeployOnce(api: api, traits: traits)

        session = api.createSession()
        guard session != 0 else {
            throw NativeChineseRimeBridgeError.sessionUnavailable
        }

        didStart = true
        try selectSchema(for: mode)
        state = readState()
        status = .ready
    }

    public func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState {
        self.mode = mode
        try ensureStarted()
        guard mode.isChinese else {
            api.cleanComposition(session)
            state = .init()
            return state
        }

        api.cleanComposition(session)
        try selectSchema(for: mode)
        state = readState()
        return state
    }

    public func input(_ text: String) async throws -> ChineseCompositionState {
        try ensureStarted()
        var handledAny = false
        for scalar in text.unicodeScalars {
            handledAny = api.processKeyCode(Int32(scalar.value), modifier: 0, andSession: session) || handledAny
        }
        guard handledAny || text.isEmpty else {
            throw NativeChineseRimeBridgeError.inputRejected(text)
        }
        state = readState()
        return state
    }

    public func selectCandidate(at index: Int) async throws -> ChineseCompositionState {
        try ensureStarted()
        _ = api.selectCandidate(session, andIndex: Int32(index))
        state = readState()
        return state
    }

    public func deleteBackward() async throws -> ChineseCompositionState {
        try ensureStarted()
        _ = api.processKeyCode(0xFF08, modifier: 0, andSession: session)
        state = readState()
        return state
    }

    public func reset() async {
        guard session != 0 else {
            state = .init()
            return
        }
        api.cleanComposition(session)
        state = .init()
    }

    public func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] {
        try ensureStarted()
        let raw = api.getCandidateWith(Int32(offset), andCount: Int32(count), andSession: session) ?? []
        return raw.enumerated().map { idx, candidate in
            CandidateSuggestion(
                index: offset + idx,
                label: "\(offset + idx + 1)",
                text: candidate.text ?? "",
                title: candidate.text ?? "",
                isAutocomplete: false,
                subtitle: candidate.comment
            )
        }
    }

    public func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState {
        try ensureStarted()
        // Re-input from scratch: clean the composition and input the replacement
        // pinyin as a single key sequence.
        api.cleanComposition(session)
        for scalar in replacement.unicodeScalars {
            _ = api.processKeyCode(Int32(scalar.value), modifier: 0, andSession: session)
        }
        state = readState()
        return state
    }

    private func ensureStarted() throws {
        guard didStart, session != 0 else {
            throw NativeChineseRimeBridgeError.sessionUnavailable
        }
    }

    private static func setupAndDeployOnce(api: IRimeAPI, traits: IRimeTraits) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        if !didSetup {
            api.setup(traits)
            didSetup = true
        }
        guard !didInitializeAndDeploy else { return }

        api.initialize(traits)
        api.deployerInitialize(traits)
        guard api.deploy() else {
            throw NativeChineseRimeBridgeError.deploymentFailed
        }
        didInitializeAndDeploy = true
    }

    private func selectSchema(for mode: ChineseInputMode) throws {
        let schemaID = mode == .chineseNineGrid ? "t9" : "rime_ice"
        guard api.selectSchema(session, andSchemaId: schemaID) else {
            throw NativeChineseRimeBridgeError.schemaSelectionFailed(schemaID)
        }
    }

    private func readState() -> ChineseCompositionState {
        let context = api.getContext(session)
        let status = api.getStatus(session)
        let commitText = api.getCommit(session)
        let nonEmptyCommit = commitText?.isEmpty == false ? commitText : nil

        guard status?.isComposing == true else {
            if nonEmptyCommit != nil {
                api.cleanComposition(session)
            }
            return .init(commitText: nonEmptyCommit)
        }

        let candidates = (api.getCandidateList(session) ?? []).enumerated().map { offset, candidate in
            CandidateSuggestion(
                index: offset,
                label: "\(offset + 1)",
                text: candidate.text ?? "",
                title: candidate.text ?? "",
                isAutocomplete: offset == 0,
                subtitle: candidate.comment
            )
        }

        return ChineseCompositionState(
            preedit: context?.composition?.preedit ?? api.getInput(session) ?? "",
            candidates: candidates,
            commitText: nonEmptyCommit
        )
    }

    private static func defaultDirectories() -> RimeDataDirectories {
        let sandboxRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Rime", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MashangxieRime", isDirectory: true)
        let appGroupRoot: URL
        if canAttemptAppGroupLookup {
            appGroupRoot = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mashangxie.ios")?
                .appendingPathComponent("Rime", isDirectory: true)
                ?? sandboxRoot.appendingPathComponent("AppGroupFallback", isDirectory: true)
        } else {
            appGroupRoot = sandboxRoot.appendingPathComponent("AppGroupUnavailable", isDirectory: true)
        }
        return RimeDataDirectories(appGroupRoot: appGroupRoot, sandboxRoot: sandboxRoot)
    }

    private static var canAttemptAppGroupLookup: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        switch bundleID {
        case "com.mashangxie.ios", "com.mashangxie.ios.keyboard":
            return true
        default:
            return !bundleID.hasPrefix("com.mashangxie.ios.")
        }
    }

    private static func defaultResourceBundle() -> Bundle {
        final class BundleToken {}
        return Bundle(for: BundleToken.self)
    }
}
