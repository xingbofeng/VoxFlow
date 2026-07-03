enum NotesRecordingHUDPresentation {
    static func streamingSnapshot(text: String, isFinal: Bool) -> VoiceHUDFeatureController.Snapshot? {
        guard !isFinal else { return nil }
        return .notesStreamingText(text)
    }
}
