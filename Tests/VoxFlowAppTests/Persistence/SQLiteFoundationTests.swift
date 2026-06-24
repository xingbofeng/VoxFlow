import XCTest
@testable import VoxFlowApp

final class SQLiteFoundationTests: XCTestCase {
    func testConnectionExecutesAndQueriesRows() throws {
        let connection = try SQLiteConnection.inMemory()
        try connection.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")

        let insert = try connection.prepare("INSERT INTO items (name) VALUES (?)")
        try insert.bind("VoiceInput", at: 1)
        XCTAssertFalse(try insert.step())

        let query = try connection.prepare("SELECT name FROM items WHERE id = 1")
        XCTAssertTrue(try query.step())
        XCTAssertEqual(query.columnString(at: 0), "VoiceInput")
        XCTAssertFalse(try query.step())
    }

    func testDatabaseQueueRunsReadAndWriteBlocksAgainstSameConnection() throws {
        let queue = try DatabaseQueue(connection: .inMemory())

        try queue.write { connection in
            try connection.execute("CREATE TABLE counters (value INTEGER NOT NULL)")
            let statement = try connection.prepare("INSERT INTO counters (value) VALUES (?)")
            try statement.bind(42, at: 1)
            _ = try statement.step()
        }

        let value = try queue.read { connection in
            let statement = try connection.prepare("SELECT value FROM counters")
            XCTAssertTrue(try statement.step())
            return statement.columnInt(at: 0)
        }

        XCTAssertEqual(value, 42)
    }

    func testMigratorCreatesMigrationTableAndRecordsAppliedMigration() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(id: 1, name: "create_history") { connection in
                try connection.execute("CREATE TABLE history (id TEXT PRIMARY KEY)")
            }
        ])

        try migrator.migrate(queue)

        let applied = try queue.read { connection in
            let statement = try connection.prepare(
                "SELECT name FROM schema_migrations WHERE id = 1"
            )
            XCTAssertTrue(try statement.step())
            return statement.columnString(at: 0)
        }
        XCTAssertEqual(applied, "create_history")
    }

    func testMigratorDoesNotRunAppliedMigrationTwice() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        let counter = Counter()
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(id: 1, name: "create_notes") { connection in
                counter.value += 1
                try connection.execute("CREATE TABLE notes (id TEXT PRIMARY KEY)")
            }
        ])

        try migrator.migrate(queue)
        try migrator.migrate(queue)

        XCTAssertEqual(counter.value, 1)
    }

    func testAppDatabaseInitialMigrationCreatesRequiredTables() throws {
        let queue = try DatabaseQueue(connection: .inMemory())

        try AppDatabase.migrator().migrate(queue)

        let tables = try queue.read { connection in
            try tableNames(on: connection)
        }

        XCTAssertTrue(tables.isSuperset(of: [
            "schema_migrations",
            "dictation_history",
            "style_profiles",
            "asr_providers",
            "llm_providers",
            "transcription_jobs",
            "notes",
            "app_settings",
            "voice_correction_rules",
            "voice_correction_events",
            "voice_correction_learning_suppression",
        ]))
        XCTAssertFalse(tables.contains("glossary_terms"))
        XCTAssertFalse(tables.contains("replacement_rules"))
    }

    func testLLMProvidersStoreOnlyKeychainReference() throws {
        let queue = try DatabaseQueue(connection: .inMemory())

        try AppDatabase.migrator().migrate(queue)

        let columns = try queue.read { connection in
            try columnNames(table: "llm_providers", on: connection)
        }

        XCTAssertTrue(columns.contains("api_key_ref"))
        XCTAssertFalse(columns.contains("api_key"))
        XCTAssertFalse(columns.contains("apiKey"))
    }

    func testVoiceTaskAssetBackfillMigrationImportsCompletedVoiceTasks() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try queue.write { connection in
            try connection.execute(try AppDatabase.loadBundledSchemaSQL())
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                )
                """
            )
            for id in 1...12 {
                let statement = try connection.prepare(
                    """
                    INSERT INTO schema_migrations (id, name, applied_at)
                    VALUES (?, ?, ?)
                    """
                )
                try statement.bind(id, at: 1)
                try statement.bind("migration-\(id)", at: 2)
                try statement.bind("2026-06-23T00:00:00Z", at: 3)
                _ = try statement.step()
            }
            try insertVoiceTask(
                connection,
                id: "agent-task",
                mode: "agentDispatch",
                status: "completed",
                rawTranscript: "什么意思",
                finalText: "生成后的指令",
                outputResult: #"{"kind":"inserted"}"#
            )
            try insertVoiceTask(
                connection,
                id: "dictation-task",
                mode: "dictation",
                status: "completed",
                rawTranscript: "普通听写原文",
                finalText: "普通听写修正后文本",
                outputResult: #"{"kind":"inserted"}"#
            )
            try insertVoiceTask(
                connection,
                id: "cancelled-task",
                mode: "agentDispatch",
                status: "cancelled",
                rawTranscript: "不要导入",
                finalText: "不要导入",
                outputResult: #"{"kind":"cancelled"}"#
            )
            try insertAssetItem(
                connection,
                id: "clipboard-same-transcript",
                source: "clipboard",
                contentType: "text",
                title: "什么意思",
                text: "什么意思",
                contentHash: "clipboard-same-transcript",
                captureReason: "userCopied"
            )
        }

        try AppDatabase.migrator().migrate(queue)

        let repository = SQLiteAssetRepository(databaseQueue: queue)
        let asset = try repository.asset(id: "dictation-agent-task")
        XCTAssertEqual(asset?.source, .dictation)
        XCTAssertEqual(asset?.contentType, .text)
        XCTAssertEqual(asset?.title, "什么意思")
        XCTAssertEqual(asset?.text, "什么意思")
        XCTAssertEqual(asset?.rawText, "什么意思")
        XCTAssertEqual(asset?.captureReason, .dictationCompleted)
        let dictationAsset = try repository.asset(id: "dictation-dictation-task")
        XCTAssertEqual(dictationAsset?.text, "普通听写修正后文本")
        XCTAssertEqual(dictationAsset?.rawText, "普通听写原文")
        XCTAssertEqual(try repository.asset(id: "clipboard-same-transcript")?.source, .clipboard)
        XCTAssertNil(try repository.asset(id: "dictation-cancelled-task"))
    }

    func testScreenshotRecordAssetBackfillMigrationImportsLegacyScreenshots() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try queue.write { connection in
            try connection.execute(try AppDatabase.loadBundledSchemaSQL())
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                )
                """
            )
            for id in 1...13 {
                let statement = try connection.prepare(
                    """
                    INSERT INTO schema_migrations (id, name, applied_at)
                    VALUES (?, ?, ?)
                    """
                )
                try statement.bind(id, at: 1)
                try statement.bind("migration-\(id)", at: 2)
                try statement.bind("2026-06-23T00:00:00Z", at: 3)
                _ = try statement.step()
            }
            try insertScreenshotRecord(
                connection,
                id: "screenshot-record",
                ocrText: "旧截图 OCR 文本",
                imagePath: "/tmp/legacy-screenshot.png"
            )
            try insertScreenshotRecord(
                connection,
                id: "deleted-screenshot",
                ocrText: "不应导入",
                imagePath: "/tmp/deleted-screenshot.png",
                deletedAt: "2026-06-24T01:00:00Z"
            )
        }

        try AppDatabase.migrator().migrate(queue)

        let repository = SQLiteAssetRepository(databaseQueue: queue)
        let asset = try repository.asset(id: "screenshot-screenshot-record")
        XCTAssertEqual(asset?.source, .screenshot)
        XCTAssertEqual(asset?.contentType, .image)
        XCTAssertEqual(asset?.title, "旧截图 OCR 文本")
        XCTAssertEqual(asset?.previewText, "旧截图 OCR 文本")
        XCTAssertEqual(asset?.text, "旧截图 OCR 文本")
        XCTAssertEqual(asset?.imagePath, "/tmp/legacy-screenshot.png")
        XCTAssertEqual(asset?.captureReason, .screenshotCaptured)
        XCTAssertNil(try repository.asset(id: "screenshot-deleted-screenshot"))
    }

    func testVoiceTaskAssetRepairMigrationImportsTasksCreatedAfterInitialBackfill() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try queue.write { connection in
            try connection.execute(try AppDatabase.loadBundledSchemaSQL())
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                )
                """
            )
            for id in 1...14 {
                let statement = try connection.prepare(
                    """
                    INSERT INTO schema_migrations (id, name, applied_at)
                    VALUES (?, ?, ?)
                    """
                )
                try statement.bind(id, at: 1)
                try statement.bind("migration-\(id)", at: 2)
                try statement.bind("2026-06-23T00:00:00Z", at: 3)
                _ = try statement.step()
            }
            try insertVoiceTask(
                connection,
                id: "late-agent-task",
                mode: "agentDispatch",
                status: "completed",
                rawTranscript: "后来的 ASR",
                finalText: "后来的生成结果",
                outputResult: #"{"kind":"inserted"}"#
            )
        }

        try AppDatabase.migrator().migrate(queue)

        let asset = try SQLiteAssetRepository(databaseQueue: queue).asset(id: "dictation-late-agent-task")
        XCTAssertEqual(asset?.source, .dictation)
        XCTAssertEqual(asset?.contentType, .text)
        XCTAssertEqual(asset?.text, "后来的 ASR")
        XCTAssertEqual(asset?.rawText, "后来的 ASR")
        XCTAssertEqual(asset?.captureReason, .dictationCompleted)
    }

    private func tableNames(on connection: SQLiteConnection) throws -> Set<String> {
        let statement = try connection.prepare(
            """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            """
        )
        var names = Set<String>()
        while try statement.step() {
            if let name = statement.columnString(at: 0) {
                names.insert(name)
            }
        }
        return names
    }

    private func insertVoiceTask(
        _ connection: SQLiteConnection,
        id: String,
        mode: String,
        status: String,
        rawTranscript: String = "什么意思",
        finalText: String,
        outputResult: String
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO voice_tasks (
                id,
                mode,
                stage,
                status,
                raw_transcript,
                final_text,
                output_result,
                warnings_json,
                created_at,
                updated_at,
                completed_at
            )
            VALUES (?, ?, 'processing', ?, ?, ?, ?, '[]',
                '2026-06-24T01:00:00Z',
                '2026-06-24T01:00:00Z',
                '2026-06-24T01:00:01Z'
            )
            """
        )
        try statement.bind(id, at: 1)
        try statement.bind(mode, at: 2)
        try statement.bind(status, at: 3)
        try statement.bind(rawTranscript, at: 4)
        try statement.bind(finalText, at: 5)
        try statement.bind(outputResult, at: 6)
        _ = try statement.step()
    }

    private func insertAssetItem(
        _ connection: SQLiteConnection,
        id: String,
        source: String,
        contentType: String,
        title: String,
        text: String,
        contentHash: String,
        captureReason: String
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO asset_items (
                id,
                source,
                content_type,
                title,
                preview_text,
                text,
                raw_text,
                image_path,
                file_path,
                url,
                color_value,
                source_app_name,
                source_app_bundle_id,
                content_hash,
                capture_reason,
                metadata_json,
                created_at,
                updated_at,
                deleted_at
            )
            VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?, NULL,
                '2026-06-24T00:59:00Z',
                '2026-06-24T00:59:00Z',
                NULL
            )
            """
        )
        try statement.bind(id, at: 1)
        try statement.bind(source, at: 2)
        try statement.bind(contentType, at: 3)
        try statement.bind(title, at: 4)
        try statement.bind(text, at: 5)
        try statement.bind(text, at: 6)
        try statement.bind(contentHash, at: 7)
        try statement.bind(captureReason, at: 8)
        _ = try statement.step()
    }

    private func insertScreenshotRecord(
        _ connection: SQLiteConnection,
        id: String,
        ocrText: String,
        imagePath: String,
        deletedAt: String? = nil
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO screenshot_records (
                id,
                ocr_text,
                translated_text,
                summary_text,
                image_path,
                char_count,
                is_favorited,
                created_at,
                updated_at,
                deleted_at
            )
            VALUES (?, ?, NULL, NULL, ?, 8, 0,
                '2026-06-24T01:00:00Z',
                '2026-06-24T01:00:01Z',
                ?
            )
            """
        )
        try statement.bind(id, at: 1)
        try statement.bind(ocrText, at: 2)
        try statement.bind(imagePath, at: 3)
        try statement.bind(deletedAt, at: 4)
        _ = try statement.step()
    }

    private func columnNames(table: String, on connection: SQLiteConnection) throws -> Set<String> {
        let statement = try connection.prepare("PRAGMA table_info(\(table))")
        var names = Set<String>()
        while try statement.step() {
            if let name = statement.columnString(at: 1) {
                names.insert(name)
            }
        }
        return names
    }
}

private final class Counter {
    var value = 0
}
