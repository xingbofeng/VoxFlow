import Foundation

enum StorageHealthState: Equatable {
    case persistent(databaseURL: URL)
    case readOnly(databaseURL: URL, reason: String)
    case migrationRequired(databaseURL: URL, reason: String)
    case corrupt(databaseURL: URL, reason: String)
    case unavailable(reason: String)
    case volatile(reason: String)

    var isPersistent: Bool {
        switch self {
        case .persistent, .readOnly, .migrationRequired, .corrupt:
            return true
        case .unavailable, .volatile:
            return false
        }
    }
}

struct DependencyContainer {
    let clock: any AppClock
    let paths: ApplicationSupportPaths?
    let storageHealth: StorageHealthState
    let databaseQueue: DatabaseQueue
    let credentialStore: CredentialStore
    let historyRepository: any HistoryRepository
    let styleRepository: any StyleRepository
    let asrProviderRepository: any ASRProviderRepository
    let llmProviderRepository: any LLMProviderRepository
    let transcriptionJobRepository: any TranscriptionJobRepository
    let noteRepository: any NoteRepository
    let settingsRepository: any SettingsRepository
    let correctionRuleRepository: any CorrectionRuleRepository
    let correctionSnapshotProvider: CorrectionRuleSnapshotProvider
    let voiceCorrectionProcessor: any VoiceCorrectionTextProcessing

    static func live(
        clock: any AppClock = SystemClock(),
        credentialStore: CredentialStore? = nil,
        defaults: UserDefaults = .standard
    ) throws -> DependencyContainer {
        let paths = try ApplicationSupportPaths.live()
        try paths.ensureDirectories()
        let databaseQueue = try DatabaseQueue(connection: SQLiteConnection(url: paths.databaseURL))
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)

        return try make(
            databaseQueue: databaseQueue,
            clock: clock,
            paths: paths,
            storageHealth: .persistent(databaseURL: paths.databaseURL),
            credentialStore: credentialStore ?? defaultCredentialStore(paths: paths),
            defaults: defaults
        )
    }

    static func inMemory(
        clock: any AppClock = SystemClock(),
        credentialStore: CredentialStore? = nil,
        defaults: UserDefaults = UserDefaults(suiteName: "VoxFlowApp.inMemory.\(UUID().uuidString)")!,
        storageHealth: StorageHealthState = .volatile(reason: "Using in-memory storage.")
    ) throws -> DependencyContainer {
        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        let volatilePaths = ApplicationSupportPaths(
            applicationSupportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("VoxFlowApp.inMemory.\(UUID().uuidString)", isDirectory: true)
        )
        return try make(
            databaseQueue: databaseQueue,
            clock: clock,
            paths: nil,
            storageHealth: storageHealth,
            credentialStore: credentialStore ?? defaultCredentialStore(paths: volatilePaths),
            defaults: defaults
        )
    }

    static func defaultCredentialStore(paths: ApplicationSupportPaths) -> CredentialStore {
        AppLocalCredentialStore(fileURL: paths.credentialsURL)
    }

    private static func make(
        databaseQueue: DatabaseQueue,
        clock: any AppClock,
        paths: ApplicationSupportPaths?,
        storageHealth: StorageHealthState,
        credentialStore: CredentialStore,
        defaults: UserDefaults
    ) throws -> DependencyContainer {
        let historyRepository = SQLiteHistoryRepository(databaseQueue: databaseQueue)
        let styleRepository = SQLiteStyleRepository(databaseQueue: databaseQueue)
        try BuiltInStyleSeeder.seed(styleRepository: styleRepository, clock: clock)
        let asrProviderRepository = SQLiteASRProviderRepository(databaseQueue: databaseQueue)
        let llmProviderRepository = SQLiteLLMProviderRepository(databaseQueue: databaseQueue)
        let transcriptionJobRepository = SQLiteTranscriptionJobRepository(databaseQueue: databaseQueue)
        let noteRepository = SQLiteNoteRepository(databaseQueue: databaseQueue)
        let settingsRepository = SQLiteSettingsRepository(databaseQueue: databaseQueue, clock: clock)
        let correctionRuleRepository = SQLiteCorrectionRuleRepository(databaseQueue: databaseQueue)
        let correctionSnapshotProvider = CorrectionRuleSnapshotProvider(loader: correctionRuleRepository)
        let voiceCorrectionProcessor = TranscriptPostProcessingCoordinator(
            processor: VoiceCorrectionTextProcessor(
                snapshotProvider: correctionSnapshotProvider,
                settingsRepository: settingsRepository
            )
        )

        if let paths {
            LLMDiagnosticCapture.shared.configure(
                enabled: storedBool(
                    forKey: SettingsSystemOption.llmTraceDiagnostics.rawValue,
                    in: settingsRepository,
                    defaultValue: false
                ),
                directory: paths.llmTraceDiagnosticsDirectory
            )
        }

        return DependencyContainer(
            clock: clock,
            paths: paths,
            storageHealth: storageHealth,
            databaseQueue: databaseQueue,
            credentialStore: credentialStore,
            historyRepository: historyRepository,
            styleRepository: styleRepository,
            asrProviderRepository: asrProviderRepository,
            llmProviderRepository: llmProviderRepository,
            transcriptionJobRepository: transcriptionJobRepository,
            noteRepository: noteRepository,
            settingsRepository: settingsRepository,
            correctionRuleRepository: correctionRuleRepository,
            correctionSnapshotProvider: correctionSnapshotProvider,
            voiceCorrectionProcessor: voiceCorrectionProcessor
        )
    }

    private static func storedBool(
        forKey key: String,
        in repository: any SettingsRepository,
        defaultValue: Bool
    ) -> Bool {
        struct StoredBool: Decodable {
            let value: Bool
        }

        let json: String?
        do {
            json = try repository.value(forKey: key)
        } catch {
            return defaultValue
        }
        guard
            let json,
            let data = json.data(using: .utf8),
            let stored = try? JSONDecoder().decode(StoredBool.self, from: data)
        else {
            return defaultValue
        }
        return stored.value
    }
}
