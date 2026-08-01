// AppGroup.swift
// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// App Group identifier changed to mashangxie namespace.
import Foundation

/// Entry point for the App Group shared between the Mashangxie app and the
/// Keyboard Extension. Both processes read/write through this enum so the
/// identifier stays in one place.
public enum AppGroup {
    public static let identifier = "group.com.mashangxie.ios"

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedContainerURL: URL?
    nonisolated(unsafe) private static var didResolveContainerURL = false

    /// AltStore / SideStore free-signing rewrites bundle ids, for example:
    /// `com.mashangxie.ios.HB3RM85628.keyboard`. In that shape the original
    /// App Group entitlement cannot be present, so calling App Group APIs only
    /// produces sandbox denials. Short-circuit before touching those APIs.
    public static var canAttemptAppGroupLookup: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        switch bundleID {
        case "com.mashangxie.ios", "com.mashangxie.ios.keyboard":
            return true
        default:
            return !bundleID.hasPrefix("com.mashangxie.ios.")
        }
    }

    /// Shared UserDefaults for cross-process data. Returns nil when the App Group
    /// entitlement is missing or the suite cannot be initialized (free Apple ID /
    /// AltStore / SideStore paths). Callers that absolutely require shared storage
    /// should use `defaultsIfAvailable` and fall back to a local / no-op strategy.
    ///
    /// Why this changed from `fatalError`: the iOS keyboard must keep rendering
    /// even when App Group is unavailable (see add-ios-keyboard-clipboard-fallback
    /// Phase 2). Crashing here made the entire keyboard unusable on free-signed
    /// devices, blocking even basic typing.
    public static var defaultsIfAvailable: UserDefaults? {
        guard canAttemptAppGroupLookup else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    /// Preferences storage for values that should not prevent the app or
    /// keyboard from launching when App Group is unavailable.
    ///
    /// Use this for local preferences, diagnostics UI, onboarding state,
    /// keyboard layout choices, emoji recents, and other non-contract data.
    /// Do not use it for AppGroupBridge's required cross-process dictation
    /// contract when the caller must know that sharing is unavailable.
    public static var preferences: UserDefaults {
        defaultsIfAvailable ?? .standard
    }

    /// Shared UserDefaults for cross-process data.
    ///
    /// Force-unwrap justified ONLY for code paths that are explicitly part of the
    /// AppGroupBridge (the formal paid-signing / simulator path). ClipboardBridge
    /// callers MUST use `defaultsIfAvailable` and handle nil. The keyboard startup
    /// path MUST NOT call this — use `defaultsIfAvailable` instead.
    ///
    /// Historical note: previously this was the only entry point and would
    /// `fatalError` on free-signed devices where the suite cannot be created.
    /// That behavior was removed because it crashed the keyboard on AltStore /
    /// SideStore installs even for plain typing. See `defaultsIfAvailable` for
    /// the safe variant.
    public static var defaults: UserDefaults {
        guard canAttemptAppGroupLookup else {
            fatalError("App Group '\(identifier)' is unavailable for rewritten bundle id '\(Bundle.main.bundleIdentifier ?? "unknown")'. Use defaultsIfAvailable.")
        }
        guard let defaults = UserDefaults(suiteName: identifier) else {
            // We intentionally crash here rather than silently return standard
            // defaults: callers of `defaults` are on the AppGroupBridge path
            // and would silently corrupt state if they wrote to standard UD
            // thinking it was cross-process shared. The keyboard startup path
            // must use `defaultsIfAvailable` and never reach this branch.
            //
            // If you see this crash in production:
            //  - Free-signed (AltStore/SideStore): switch BridgeMode to Clipboard
            //  - Simulator/paid signing: fix the entitlement
            fatalError("App Group '\(identifier)' not configured. Use defaultsIfAvailable for keyboard/ClipboardBridge paths.")
        }
        return defaults
    }

    /// Shared file container URL for larger data (audio, logs). nil when the
    /// entitlement is missing — callers must handle nil.
    public static var containerURL: URL? {
        guard canAttemptAppGroupLookup else { return nil }

        cacheLock.lock()
        if didResolveContainerURL {
            let cached = cachedContainerURL
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let resolved = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )

        cacheLock.lock()
        if !didResolveContainerURL {
            cachedContainerURL = resolved
            didResolveContainerURL = true
        }
        let cached = cachedContainerURL
        cacheLock.unlock()
        return cached
    }
}
