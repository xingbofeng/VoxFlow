import Foundation

final class LLMDiagnosticCapture: @unchecked Sendable {
    static let shared = LLMDiagnosticCapture()

    private struct CapturedTrace: Codable {
        let taskID: String
        let capturedAt: Date
        let trace: TextProcessingTrace
    }

    private let lock = NSLock()
    private let fileManager: FileManager
    private let retentionInterval: TimeInterval
    private let maximumTraceCount: Int
    private var directory: URL?

    init(
        fileManager: FileManager = .default,
        retentionInterval: TimeInterval = 7 * 24 * 60 * 60,
        maximumTraceCount: Int = 100
    ) {
        self.fileManager = fileManager
        self.retentionInterval = retentionInterval
        self.maximumTraceCount = max(1, maximumTraceCount)
    }

    func configure(enabled: Bool, directory: URL?) {
        lock.withLock {
            guard enabled, let directory else {
                if let directory = directory ?? self.directory {
                    try? fileManager.removeItem(at: directory)
                }
                self.directory = nil
                return
            }

            self.directory = directory
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            pruneLocked(now: Date())
        }
    }

    func capture(taskID: String, trace: TextProcessingTrace, at date: Date = Date()) {
        lock.withLock {
            guard let directory, trace.llm != nil else { return }
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let captured = CapturedTrace(
                taskID: taskID,
                capturedAt: date,
                trace: trace.redactedForDiagnosticCapture()
            )
            guard let data = try? JSONEncoder().encode(captured) else { return }

            let safeTaskID = taskID.replacingOccurrences(
                of: #"[^A-Za-z0-9_-]"#,
                with: "-",
                options: .regularExpression
            )
            let timestamp = Int64(date.timeIntervalSince1970 * 1_000)
            let fileURL = directory.appendingPathComponent(
                "trace-\(timestamp)-\(safeTaskID)-\(UUID().uuidString).json",
                isDirectory: false
            )
            try? data.write(to: fileURL, options: .atomic)
            pruneLocked(now: date)
        }
    }

    func trace(taskID: String) -> TextProcessingTrace? {
        lock.withLock {
            guard let directory,
                  let files = try? fileManager.contentsOfDirectory(
                      at: directory,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles]
                  ) else {
                return nil
            }

            return files
                .filter { $0.pathExtension == "json" }
                .compactMap { file -> CapturedTrace? in
                    guard
                        let data = try? Data(contentsOf: file),
                        let captured = try? JSONDecoder().decode(CapturedTrace.self, from: data),
                        captured.taskID == taskID
                    else {
                        return nil
                    }
                    return captured
                }
                .sorted { $0.capturedAt > $1.capturedAt }
                .first?
                .trace
        }
    }

    func clear() {
        lock.withLock {
            removeCapturedContentLocked()
        }
    }

    func prune(now: Date = Date()) {
        lock.withLock {
            pruneLocked(now: now)
        }
    }

    private func pruneLocked(now: Date) {
        guard let directory else { return }
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = now.addingTimeInterval(-retentionInterval)
        var retained: [(url: URL, capturedAt: Date)] = []
        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let captured = try? JSONDecoder().decode(CapturedTrace.self, from: data)
            else {
                try? fileManager.removeItem(at: file)
                continue
            }
            if captured.capturedAt < cutoff {
                try? fileManager.removeItem(at: file)
            } else {
                retained.append((file, captured.capturedAt))
            }
        }

        for item in retained
            .sorted(by: { $0.capturedAt > $1.capturedAt })
            .dropFirst(maximumTraceCount) {
            try? fileManager.removeItem(at: item.url)
        }
    }

    private func removeCapturedContentLocked() {
        guard let directory else { return }
        try? fileManager.removeItem(at: directory)
    }
}

private extension TextProcessingTrace {
    func redactedForDiagnosticCapture() -> TextProcessingTrace {
        guard let llm else { return self }
        return TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: llm.providerID,
                providerName: llm.providerName,
                endpoint: AppLogger.redact(llm.endpoint),
                model: llm.model,
                temperature: llm.temperature,
                timeoutSeconds: llm.timeoutSeconds,
                requestBodyJSON: AppLogger.redact(llm.requestBodyJSON),
                responseText: llm.responseText.map(AppLogger.redact),
                statusCode: llm.statusCode,
                durationMS: llm.durationMS,
                errorMessage: llm.errorMessage.map(AppLogger.redact),
                completedAt: llm.completedAt,
                // Prompt metadata is safe (kind/version/hash/ids only) and is
                // preserved through diagnostic redaction so captured traces can
                // explain which prompt version produced the request.
                promptMetadata: llm.promptMetadata
            ),
            output: output,
            contextBoost: contextBoost?.safeForPersistence(),
            voiceCorrection: voiceCorrection?.safeForPersistence(),
            // Diagnostic mode is opt-in. Preserve the route trace's safe
            // fields (IDs, version, hash, latency, reason) but drop raw
            // routerResponse, which on invalid output could echo user text.
            styleRoute: styleRoute?.safeForPersistence(),
            deterministic: deterministic?.safeForPersistence()
        )
    }
}
