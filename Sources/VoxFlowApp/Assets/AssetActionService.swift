import AppKit
import VoxFlowTextInsertion

enum AssetAction: String, CaseIterable, Equatable, Sendable {
    case paste
    case copy
    case pasteAndKeepOpen
    case quickLook
    case saveAsFile
    case delete
    case copyImage
    case pasteOCRText
    case copyOCRText
    case pasteFile
    case copyFile
    case pasteFilePath
    case copyFilePath

    // Explicitly phase-two or excluded actions. Keep them named so tests and Palette
    // filtering can assert they do not appear in v1 action panels.
    case pin
    case rerunOCR
    case attachToAIChat
}

extension AssetAction {
    var displayTitle: String {
        switch self {
        case .paste:
            return "粘贴"
        case .copy:
            return "复制"
        case .pasteAndKeepOpen:
            return "粘贴并保持打开"
        case .quickLook:
            return "快速预览"
        case .saveAsFile:
            return "另存为文件..."
        case .delete:
            return "删除"
        case .copyImage:
            return "复制图片"
        case .pasteOCRText:
            return "粘贴识别文字"
        case .copyOCRText:
            return "复制识别文字"
        case .pasteFile:
            return "粘贴文件"
        case .copyFile:
            return "复制文件"
        case .pasteFilePath:
            return "粘贴文件路径"
        case .copyFilePath:
            return "复制文件路径"
        case .pin:
            return "固定"
        case .rerunOCR:
            return "重新 OCR"
        case .attachToAIChat:
            return "附加到 AI 会话"
        }
    }
}

enum AssetActionResult: Equatable, Sendable {
    case pasted
    case copied
    case deleted
    case openedPreview
    case saveRequested
}

enum AssetActionError: Error, Equatable {
    case missingText
    case missingImage
    case missingFilePath
    case unsupportedAction
    case pasteFailed
    case pasteboardWriteFailed
}

@MainActor
final class AssetActionService {
    private let textInserter: any TextInserting
    private let pasteboard: NSPasteboard
    private let internalWriteGuard: ClipboardInternalWriteGuard
    private let repository: any AssetRepository
    private let now: () -> Date
    private let pasteShortcutPoster: any PasteShortcutPosting

    init(
        textInserter: any TextInserting,
        pasteboard: NSPasteboard = .general,
        internalWriteGuard: ClipboardInternalWriteGuard,
        repository: any AssetRepository,
        now: @escaping () -> Date = Date.init,
        pasteShortcutPoster: any PasteShortcutPosting = SystemPasteShortcutPoster()
    ) {
        self.textInserter = textInserter
        self.pasteboard = pasteboard
        self.internalWriteGuard = internalWriteGuard
        self.repository = repository
        self.now = now
        self.pasteShortcutPoster = pasteShortcutPoster
    }

    func availableActions(for asset: AssetItem) -> [AssetAction] {
        var actions: [AssetAction] = [
            .paste,
            .copy,
            .pasteAndKeepOpen,
            .quickLook,
            .saveAsFile,
        ]

        if asset.source == .screenshot || asset.contentType == .image {
            actions.append(.copyImage)
            if textValue(for: asset) != nil {
                actions.append(contentsOf: [.pasteOCRText, .copyOCRText])
            }
        }

        if asset.contentType == .file {
            actions.append(contentsOf: [.pasteFile, .copyFile, .pasteFilePath, .copyFilePath])
        }

        actions.append(.delete)
        return actions
    }

    func perform(_ action: AssetAction, on asset: AssetItem) async throws -> AssetActionResult {
        switch action {
        case .paste:
            return try await pastePrimary(asset)
        case .copy:
            return try copyPrimary(asset)
        case .pasteAndKeepOpen:
            return try await pastePrimary(asset)
        case .quickLook:
            try openPreview(asset)
            return .openedPreview
        case .saveAsFile:
            try await saveAsFile(asset)
            return .saveRequested
        case .delete:
            try repository.softDelete(id: asset.id, deletedAt: now())
            return .deleted
        case .copyImage:
            try copyImage(asset)
            return .copied
        case .pasteOCRText:
            return try await paste(text: textValue(for: asset))
        case .copyOCRText:
            try copyText(textValue(for: asset))
            return .copied
        case .pasteFile:
            try copyFile(asset)
            try postPasteShortcut()
            return .pasted
        case .copyFile:
            try copyFile(asset)
            return .copied
        case .pasteFilePath:
            return try await paste(text: filePath(for: asset))
        case .copyFilePath:
            try copyText(filePath(for: asset))
            return .copied
        case .pin, .rerunOCR, .attachToAIChat:
            throw AssetActionError.unsupportedAction
        }
    }

    private func paste(text: String?) async throws -> AssetActionResult {
        guard let text else { throw AssetActionError.missingText }
        let result = await textInserter.insert(text)
        guard result == .success else {
            throw AssetActionError.pasteFailed
        }
        return .pasted
    }

    private func pastePrimary(_ asset: AssetItem) async throws -> AssetActionResult {
        switch asset.contentType {
        case .image:
            try copyImage(asset)
            try postPasteShortcut()
            return .pasted
        case .file:
            try copyFile(asset)
            try postPasteShortcut()
            return .pasted
        case .text, .link, .color:
            return try await paste(text: primaryText(for: asset))
        }
    }

    private func copyPrimary(_ asset: AssetItem) throws -> AssetActionResult {
        switch asset.contentType {
        case .image:
            try copyImage(asset)
        case .file:
            try copyFile(asset)
        case .text, .link, .color:
            try copyText(primaryText(for: asset))
        }
        return .copied
    }

    private func copyText(_ text: String?) throws {
        guard let text else { throw AssetActionError.missingText }
        guard internalWriteGuard.writeInternalString(text, to: pasteboard) else {
            throw AssetActionError.pasteboardWriteFailed
        }
    }

    /// Adapted from Stash PasteService.swift (MIT): https://github.com/hex/Stash
    /// and Maccy Clipboard.swift (MIT): https://github.com/p0deje/Maccy
    private func copyFile(_ asset: AssetItem) throws {
        let path = try filePath(for: asset)
        pasteboard.clearContents()
        let wrote = pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        if wrote {
            internalWriteGuard.markInternalWrite(changeCount: pasteboard.changeCount)
        } else {
            throw AssetActionError.pasteboardWriteFailed
        }
    }

    private func copyImage(_ asset: AssetItem) throws {
        guard let imagePath = asset.imagePath,
              let image = NSImage(contentsOfFile: imagePath) else {
            throw AssetActionError.missingImage
        }
        pasteboard.clearContents()
        let wrote = pasteboard.writeObjects([image])
        if wrote {
            internalWriteGuard.markInternalWrite(changeCount: pasteboard.changeCount)
        } else {
            throw AssetActionError.pasteboardWriteFailed
        }
    }

    private func openPreview(_ asset: AssetItem) throws {
        let url: URL
        if let path = asset.filePath ?? asset.imagePath {
            url = URL(fileURLWithPath: path)
        } else {
            let text = try textForFileExport(asset)
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voxflow-asset-preview-\(asset.id).txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func saveAsFile(_ asset: AssetItem) async throws {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFileName(for: asset)
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        if let sourcePath = asset.filePath ?? asset.imagePath {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        let text = try textForFileExport(asset)
        try text.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    private func textForFileExport(_ asset: AssetItem) throws -> String {
        guard let text = primaryText(for: asset) else {
            throw AssetActionError.missingText
        }
        return text
    }

    private func suggestedFileName(for asset: AssetItem) -> String {
        if let path = asset.filePath ?? asset.imagePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        let sanitizedTitle = asset.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (sanitizedTitle.isEmpty ? "VoxFlow Asset" : sanitizedTitle) + ".txt"
    }

    private func postPasteShortcut() throws {
        do {
            try pasteShortcutPoster.postPasteShortcut()
        } catch {
            throw AssetActionError.pasteFailed
        }
    }

    private func primaryText(for asset: AssetItem) -> String? {
        switch asset.contentType {
        case .text:
            return textValue(for: asset)
        case .link:
            return asset.url ?? textValue(for: asset)
        case .color:
            return asset.colorValue ?? textValue(for: asset)
        case .file:
            return asset.filePath ?? textValue(for: asset)
        case .image:
            return textValue(for: asset)
        }
    }

    private func textValue(for asset: AssetItem) -> String? {
        let candidates = [asset.text, asset.previewText, asset.rawText]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func filePath(for asset: AssetItem) throws -> String {
        guard let path = asset.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw AssetActionError.missingFilePath
        }
        return path
    }
}
