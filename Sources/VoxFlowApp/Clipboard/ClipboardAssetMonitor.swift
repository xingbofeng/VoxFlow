import AppKit

@MainActor
final class ClipboardAssetMonitor {
    private let pasteboard: NSPasteboard
    private let repository: any AssetRepository
    private let internalWriteGuard: ClipboardInternalWriteGuard
    private let sourceApplicationProvider: () -> ClipboardSourceApplication?
    private let imageDataWriter: ((Data, String) throws -> String)?
    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        pasteboard: NSPasteboard = .general,
        repository: any AssetRepository,
        internalWriteGuard: ClipboardInternalWriteGuard,
        sourceApplicationProvider: @escaping () -> ClipboardSourceApplication? = {
            let app = NSWorkspace.shared.frontmostApplication
            return ClipboardSourceApplication(
                name: app?.localizedName,
                bundleID: app?.bundleIdentifier
            )
        },
        imageDataWriter: ((Data, String) throws -> String)? = nil
    ) {
        self.pasteboard = pasteboard
        self.repository = repository
        self.internalWriteGuard = internalWriteGuard
        self.sourceApplicationProvider = sourceApplicationProvider
        self.imageDataWriter = imageDataWriter
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Adapted from Stash ClipboardMonitor.swift (MIT): https://github.com/hex/Stash
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                do {
                    _ = try self?.processIfChanged()
                } catch {
                    AppLogger.general.error("clipboard_asset_monitor_failed error=\(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func processIfChanged(now: Date = Date()) throws -> AssetItem? {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return nil
        }
        lastChangeCount = currentChangeCount
        return try processCurrentPasteboard(changeCount: currentChangeCount, now: now)
    }

    @discardableResult
    func processCurrentPasteboard(
        changeCount: Int,
        now: Date = Date()
    ) throws -> AssetItem? {
        guard let item = pasteboard.pasteboardItems?.first else {
            return nil
        }

        guard !internalWriteGuard.shouldIgnore(
            changeCount: changeCount,
            types: item.types
        ) else {
            return nil
        }

        guard !item.types.contains(.universalClipboard) else {
            return nil
        }

        guard let candidate = ClipboardAssetCandidateExtractor.candidate(
            from: pasteboard,
            item: item
        ) else {
            return nil
        }

        let imagePath = try candidate.imageData.map { data in
            try imageDataWriter?(data, candidate.contentHash)
        } ?? nil
        let assetID = "clipboard-\(candidate.contentHash)"
        let existingAsset = try repository.asset(id: assetID)
        let asset = try candidate.makeAsset(
            now: now,
            createdAt: existingAsset?.createdAt,
            sourceApplication: sourceApplicationProvider(),
            imagePath: imagePath
        )
        try repository.save(asset)
        return asset
    }
}
