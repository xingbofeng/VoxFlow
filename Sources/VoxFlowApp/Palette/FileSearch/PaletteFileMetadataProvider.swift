import Foundation
import UniformTypeIdentifiers

@MainActor
protocol PaletteFileMetadataProviding {
    func metadata(for file: PaletteFileItem) async -> PaletteFileMetadata
}

@MainActor
struct SystemPaletteFileMetadataProvider: PaletteFileMetadataProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func metadata(for file: PaletteFileItem) async -> PaletteFileMetadata {
        let path = file.url.path
        let attributes = (try? fileManager.attributesOfItem(atPath: path)) ?? [:]
        let typeIdentifier = file.contentTypeIdentifier
        let type = typeIdentifier.flatMap(UTType.init)

        return PaletteFileMetadata(
            name: file.name,
            path: path,
            kind: type?.localizedDescription ?? fileKindFallback(for: file),
            sizeDescription: sizeDescription(from: attributes[.size]),
            createdAt: attributes[.creationDate] as? Date,
            modifiedAt: (attributes[.modificationDate] as? Date) ?? file.modifiedAt,
            previewKind: previewKind(for: file, type: type)
        )
    }

    private func fileKindFallback(for file: PaletteFileItem) -> String {
        file.isDirectory
            ? L10n.localize("palette.files.kind.folder", comment: "")
            : L10n.localize("palette.files.kind.file", comment: "")
    }

    private func sizeDescription(from value: Any?) -> String? {
        guard let size = value as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func previewKind(for file: PaletteFileItem, type: UTType?) -> PaletteFilePreviewKind {
        if file.isDirectory {
            return .folder
        }
        if type?.conforms(to: .image) == true {
            return .image(file.url)
        }
        return .generic
    }
}
