import Foundation

struct DependencyContainer {
    let clock: any AppClock
    let paths: ApplicationSupportPaths?
    let databaseQueue: DatabaseQueue
    let credentialStore: CredentialStore
    let historyRepository: any HistoryRepository
    let glossaryRepository: any GlossaryRepository
    let replacementRuleRepository: any ReplacementRuleRepository
    let styleRepository: any StyleRepository
    let asrProviderRepository: any ASRProviderRepository
    let llmProviderRepository: any LLMProviderRepository
    let transcriptionJobRepository: any TranscriptionJobRepository
    let noteRepository: any NoteRepository
    let settingsRepository: any SettingsRepository

    static func live(
        clock: any AppClock = SystemClock(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
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
            credentialStore: credentialStore,
            defaults: defaults
        )
    }

    static func inMemory(
        clock: any AppClock = SystemClock(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        defaults: UserDefaults = UserDefaults(suiteName: "VoiceInputApp.inMemory.\(UUID().uuidString)")!
    ) throws -> DependencyContainer {
        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        return try make(
            databaseQueue: databaseQueue,
            clock: clock,
            paths: nil,
            credentialStore: credentialStore,
            defaults: defaults
        )
    }

    private static func make(
        databaseQueue: DatabaseQueue,
        clock: any AppClock,
        paths: ApplicationSupportPaths?,
        credentialStore: CredentialStore,
        defaults: UserDefaults
    ) throws -> DependencyContainer {
        let historyRepository = SQLiteHistoryRepository(databaseQueue: databaseQueue)
        let glossaryRepository = SQLiteGlossaryRepository(databaseQueue: databaseQueue)
        let replacementRuleRepository = SQLiteReplacementRuleRepository(databaseQueue: databaseQueue)
        let styleRepository = SQLiteStyleRepository(databaseQueue: databaseQueue)
        try BuiltInStyleSeeder.seed(styleRepository: styleRepository, clock: clock)
        let asrProviderRepository = SQLiteASRProviderRepository(databaseQueue: databaseQueue)
        let llmProviderRepository = SQLiteLLMProviderRepository(databaseQueue: databaseQueue)
        let transcriptionJobRepository = SQLiteTranscriptionJobRepository(databaseQueue: databaseQueue)
        let noteRepository = SQLiteNoteRepository(databaseQueue: databaseQueue)
        let settingsRepository = SQLiteSettingsRepository(databaseQueue: databaseQueue, clock: clock)
        try LegacyConfigurationMigrator.migrate(
            defaults: defaults,
            credentialStore: credentialStore,
            llmProviderRepository: llmProviderRepository,
            styleRepository: styleRepository,
            settingsRepository: settingsRepository,
            clock: clock
        )

        return DependencyContainer(
            clock: clock,
            paths: paths,
            databaseQueue: databaseQueue,
            credentialStore: credentialStore,
            historyRepository: historyRepository,
            glossaryRepository: glossaryRepository,
            replacementRuleRepository: replacementRuleRepository,
            styleRepository: styleRepository,
            asrProviderRepository: asrProviderRepository,
            llmProviderRepository: llmProviderRepository,
            transcriptionJobRepository: transcriptionJobRepository,
            noteRepository: noteRepository,
            settingsRepository: settingsRepository
        )
    }
}
