import Foundation

struct PaletteFileItem: Equatable, Identifiable, Sendable {
    let id: String
    let url: URL
    let name: String
    let displayPath: String
    let isDirectory: Bool
    let contentTypeIdentifier: String?
    let lastUsedAt: Date?
    let modifiedAt: Date?

    init(
        id: String? = nil,
        url: URL,
        name: String,
        displayPath: String,
        isDirectory: Bool,
        contentTypeIdentifier: String?,
        lastUsedAt: Date? = nil,
        modifiedAt: Date?
    ) {
        self.id = id ?? url.absoluteString
        self.url = url
        self.name = name
        self.displayPath = displayPath
        self.isDirectory = isDirectory
        self.contentTypeIdentifier = contentTypeIdentifier
        self.lastUsedAt = lastUsedAt
        self.modifiedAt = modifiedAt
    }
}

enum PaletteFilePreviewKind: Equatable, Sendable {
    case generic
    case folder
    case image(URL)
}

struct PaletteFileMetadata: Equatable, Sendable {
    let name: String
    let path: String
    let kind: String?
    let sizeDescription: String?
    let createdAt: Date?
    let modifiedAt: Date?
    let previewKind: PaletteFilePreviewKind
}

enum PaletteFileAction: String, CaseIterable, Equatable, Sendable {
    case open
    case showInFinder
    case quickLook
    case copyPath
    case copyName
}

extension PaletteFileAction {
    var displayTitle: String {
        switch self {
        case .open:
            return L10n.localize("palette.file_action.open", comment: "")
        case .showInFinder:
            return L10n.localize("palette.file_action.show_in_finder", comment: "")
        case .quickLook:
            return L10n.localize("palette.file_action.quick_look", comment: "")
        case .copyPath:
            return L10n.localize("palette.file_action.copy_path", comment: "")
        case .copyName:
            return L10n.localize("palette.file_action.copy_name", comment: "")
        }
    }
}
