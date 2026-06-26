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
    let assetRepository: any AssetRepository
    let styleRepository: any StyleRepository
    let asrProviderRepository: any ASRProviderRepository
    let llmProviderRepository: any LLMProviderRepository
    let transcriptionJobRepository: any TranscriptionJobRepository
    let noteRepository: any NoteRepository
    let screenshotRecordRepository: any ScreenshotRecordRepository
    let mediaRecordRepository: any MediaRecordRepository
    let settingsRepository: any SettingsRepository
    let correctionTargetRepository: any CorrectionTargetRepository
    let correctionRuleRepository: any CorrectionRuleRepository
    let correctionSnapshotProvider: CorrectionRuleSnapshotProvider
    let voiceCorrectionProcessor: any VoiceCorrectionTextProcessing

    static func live(
        clock: any AppClock = SystemClock(),
        credentialStore: CredentialStore? = nil,
        defaults: UserDefaults = .standard
    ) throws -> DependencyContainer {
        AppLogger.general.info("DependencyContainer.live start")
        let paths = try ApplicationSupportPaths.live()
        AppLogger.general.debug("DependencyContainer paths ready: \(paths.rootDirectory.path)")
        try paths.ensureDirectories()
        cleanupStaleScreenRecordingTemporaryFiles(paths: paths, now: clock.now)
        let databaseQueue = try DatabaseQueue(connection: SQLiteConnection(url: paths.databaseURL))
        AppLogger.general.debug("DependencyContainer databaseQueue created")
        #if DEBUG
        try AppDatabase.bootstrapFromSnapshotIfEnabled(on: databaseQueue)
        #endif
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        AppLogger.general.debug("DependencyContainer migration completed")
        try AppDatabase.ensureRequiredRuntimeTables(databaseQueue)
        AppLogger.general.debug("DependencyContainer runtime tables verified")

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
        AppLogger.general.info("DependencyContainer.inMemory start")
        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        AppLogger.general.debug("DependencyContainer in-memory DB queue created")
        #if DEBUG
        try AppDatabase.bootstrapFromSnapshotIfEnabled(on: databaseQueue)
        #endif
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        AppLogger.general.debug("DependencyContainer in-memory migration completed")
        try AppDatabase.ensureRequiredRuntimeTables(databaseQueue)
        AppLogger.general.debug("DependencyContainer in-memory runtime tables verified")
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

    static func cleanupStaleScreenRecordingTemporaryFiles(
        paths: ApplicationSupportPaths,
        now: Date,
        staleAge: TimeInterval = 24 * 60 * 60
    ) {
        ScreenRecordingFileStorage(paths: paths)
            .cleanupStaleTemporaryFiles(olderThan: now.addingTimeInterval(-staleAge))
    }

    private static func make(
        databaseQueue: DatabaseQueue,
        clock: any AppClock,
        paths: ApplicationSupportPaths?,
        storageHealth: StorageHealthState,
        credentialStore: CredentialStore,
        defaults: UserDefaults
    ) throws -> DependencyContainer {
        AppLogger.general.debug("DependencyContainer.make initialize repositories")
        let historyRepository = SQLiteHistoryRepository(databaseQueue: databaseQueue)
        let assetRepository = SQLiteAssetRepository(databaseQueue: databaseQueue)
        let styleRepository = SQLiteStyleRepository(databaseQueue: databaseQueue)
        try BuiltInStyleSeeder.seed(styleRepository: styleRepository, clock: clock)
        let asrProviderRepository = SQLiteASRProviderRepository(databaseQueue: databaseQueue)
        let llmProviderRepository = SQLiteLLMProviderRepository(databaseQueue: databaseQueue)
        let transcriptionJobRepository = SQLiteTranscriptionJobRepository(databaseQueue: databaseQueue)
        let noteRepository = SQLiteNoteRepository(databaseQueue: databaseQueue)
        let screenshotRecordRepository = SQLiteScreenshotRecordRepository(databaseQueue: databaseQueue)
        let mediaRecordRepository = SQLiteMediaRecordRepository(
            databaseQueue: databaseQueue,
            now: { clock.now }
        )
        let settingsRepository = SQLiteSettingsRepository(databaseQueue: databaseQueue, clock: clock)
        let correctionTargetRepository = SQLiteCorrectionTargetRepository(databaseQueue: databaseQueue)
        let correctionRuleRepository = SQLiteCorrectionRuleRepository(databaseQueue: databaseQueue)
        let correctionSnapshotProvider = CorrectionRuleSnapshotProvider(loader: correctionRuleRepository)
        let voiceCorrectionProcessor = TranscriptPostProcessingCoordinator(
            processor: VoiceCorrectionTextProcessor(
                snapshotProvider: correctionSnapshotProvider,
                settingsRepository: settingsRepository,
                usageRecorder: correctionRuleRepository
            )
        )

        if let paths {
            AppLogger.general.debug("DependencyContainer.make enabling llm diagnostics")
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
            assetRepository: assetRepository,
            styleRepository: styleRepository,
            asrProviderRepository: asrProviderRepository,
            llmProviderRepository: llmProviderRepository,
            transcriptionJobRepository: transcriptionJobRepository,
            noteRepository: noteRepository,
            screenshotRecordRepository: screenshotRecordRepository,
            mediaRecordRepository: mediaRecordRepository,
            settingsRepository: settingsRepository,
            correctionTargetRepository: correctionTargetRepository,
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
