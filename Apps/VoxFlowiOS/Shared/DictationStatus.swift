// DictationStatus.swift
// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// No identifier changes needed — enum cases are brand-neutral.
import Foundation

/// Represents the current state of a dictation round-trip.
/// Written to App Group UserDefaults so both processes can track progress.
public enum DictationStatus: String, Codable {
    case idle         // No dictation in progress
    case requested    // Keyboard requested recording via shared state / URL scheme
    case recording    // Main app is recording audio
    case transcribing // Main app is running transcription
    case ready        // Transcription result available in shared storage
    case failed       // Something went wrong
}
