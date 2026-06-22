struct TranscriptionSession {
    private var latestText = ""
    private var receivedFinalResult = false
    private var released = false
    private var completed = false

    mutating func update(text: String, isFinal: Bool) -> String? {
        AppLogger.general.debug("TranscriptionSession update textLen=\(text.count) isFinal=\(isFinal)")
        guard !completed else { return nil }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            latestText = text
        }
        receivedFinalResult = receivedFinalResult || isFinal
        return released && receivedFinalResult ? complete() : nil
    }

    mutating func release() -> String? {
        AppLogger.general.debug("TranscriptionSession release")
        guard !completed else { return nil }
        released = true
        return receivedFinalResult ? complete() : nil
    }

    mutating func timeout() -> String? {
        AppLogger.general.debug("TranscriptionSession timeout released=\(released)")
        guard released, !completed else { return nil }
        return complete()
    }

    mutating func fallbackToLatestText() -> String? {
        AppLogger.general.debug("TranscriptionSession fallbackToLatestText")
        guard !completed else { return nil }
        return complete()
    }

    private mutating func complete() -> String {
        completed = true
        return latestText
    }
}
