import AppKit
import Combine
import CoreGraphics
import Foundation

struct TextEditingDraft: Equatable, Sendable {
    let elementID: UUID?
    let position: CGPoint
    var displayText: String
    let style: ScreenshotAnnotationTextStyle
}

@MainActor
public protocol AnnotationImageSaving: AnyObject {
    @discardableResult
    func savePNG(image: CGImage) throws -> Bool

    func savePNG(
        image: CGImage,
        attachedTo hostWindow: NSWindow,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
}

public extension AnnotationImageSaving {
    func savePNG(
        image: CGImage,
        attachedTo hostWindow: NSWindow,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        do {
            completion(.success(try savePNG(image: image)))
        } catch {
            completion(.failure(error))
        }
    }

    @discardableResult
    func savePNG(image: CGImage) throws -> Bool {
        guard let hostWindow = NSApp.keyWindow else {
            throw AnnotationImageSaveError.savePanelHostUnavailable
        }

        var saveResult: Result<Bool, Error>?
        savePNG(image: image, attachedTo: hostWindow) { result in
            saveResult = result
        }
        while saveResult == nil {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return try saveResult!.get()
    }
}

@MainActor
public protocol ScreenshotSavePanelPresenting: AnnotationImageSaving {}

@MainActor
public final class AnnotationEditorViewModel: ObservableObject {
    public let image: CGImage
    @Published public private(set) var document: AnnotationDocument
    @Published public private(set) var isFinished: Bool
    @Published public private(set) var isCancelled: Bool
    @Published public private(set) var saveError: Error?
    @Published public private(set) var currentStyle: ScreenshotAnnotationStyle
    @Published public private(set) var currentTextStyle: ScreenshotAnnotationTextStyle
    @Published private(set) var textEditingDraft: TextEditingDraft?

    private let renderer: any AnnotationRendering
    private let imageSaver: any AnnotationImageSaving
    private let savePanelHostWindowProvider: @MainActor () -> NSWindow?
    private var copiedElements: [AnnotationElement] = []

    public init(
        image: CGImage,
        document: AnnotationDocument = AnnotationDocument(),
        renderer: any AnnotationRendering = AnnotationRenderer(),
        imageSaver: any AnnotationImageSaving = SystemAnnotationImageSaver(),
        savePanelHostWindowProvider: @escaping @MainActor () -> NSWindow? = {
            let screenshotHost = NSApp.windows
                .filter { $0.isVisible && $0.level.rawValue >= NSWindow.Level.floating.rawValue }
                .max { $0.level.rawValue < $1.level.rawValue }
            return screenshotHost ?? NSApp.keyWindow
        }
    ) {
        self.image = image
        self.document = document
        self.renderer = renderer
        self.imageSaver = imageSaver
        self.savePanelHostWindowProvider = savePanelHostWindowProvider
        self.isFinished = false
        self.isCancelled = false
        self.saveError = nil
        self.currentStyle = .default
        self.currentTextStyle = .default
    }

    public func add(_ element: AnnotationElement) {
        commitTextEditing()
        document.add(element)
    }

    public func selectElement(id: UUID?) {
        document.selectElement(id: id)
    }

    public func selectElement(at point: CGPoint) {
        document.selectElement(id: document.hitTestElement(at: point))
    }

    public func toggleElementSelection(id: UUID) {
        document.toggleElementSelection(id: id)
    }

    public func toggleElementSelection(at point: CGPoint) {
        guard let hitID = document.hitTestElement(at: point) else {
            return
        }
        document.toggleElementSelection(id: hitID)
    }

    public func selectElements(
        in rect: CGRect,
        extendingSelection: Bool = false
    ) {
        document.selectElements(intersecting: rect, extendingSelection: extendingSelection)
    }

    public func beginUndoGroup() {
        document.beginUndoGroup()
    }

    public func moveSelectedElement(by offset: CGSize, recordsUndo: Bool = true) {
        document.moveSelectedElement(by: offset, recordsUndo: recordsUndo)
    }

    public func resizeSelectedElement(
        handle: AnnotationResizeHandle,
        to point: CGPoint,
        recordsUndo: Bool = true
    ) {
        document.resizeSelectedElement(handle: handle, to: point, recordsUndo: recordsUndo)
    }

    public func deleteSelectedElement() {
        document.deleteSelectedElement()
    }

    public func copySelectedElement() {
        let selectedIDs = Set(document.selectedElementIDs)
        copiedElements = document.elements.filter { selectedIDs.contains($0.id) }
    }

    public func pasteCopiedElement(offset: CGSize = CGSize(width: 15, height: 15)) {
        guard !copiedElements.isEmpty else {
            return
        }
        var nextNumber = document.elements.filter { $0.kind == .numberedMarker }.count + 1
        let pastedElements = copiedElements.map { element in
            defer {
                if element.kind == .numberedMarker {
                    nextNumber += 1
                }
            }
            return element.duplicated(
                offset: offset,
                numberedMarkerNumber: element.kind == .numberedMarker ? nextNumber : nil
            )
        }
        document.add(contentsOf: pastedElements)
    }

    public func duplicateSelectedElement(offset: CGSize = CGSize(width: 15, height: 15)) {
        copySelectedElement()
        pasteCopiedElement(offset: offset)
    }

    public func setAnnotationColor(_ color: ScreenshotAnnotationColor) {
        currentStyle.color = color
        currentTextStyle.color = color
        document.updateSelectedStyle(currentStyle)
    }

    public func setLineWidth(_ lineWidth: CGFloat) {
        currentStyle.lineWidth = lineWidth
        document.updateSelectedStyle(currentStyle)
    }

    public func setFontSize(_ fontSize: CGFloat) {
        currentTextStyle.fontSize = fontSize
        document.updateSelectedTextFontSize(fontSize)
    }

    public func undo() {
        document.undo()
    }

    public func redo() {
        document.redo()
    }

    public func complete() throws -> CGImage {
        commitTextEditing()
        let renderedImage = try renderedImage()
        isFinished = true
        return renderedImage
    }

    public func download() throws {
        commitTextEditing()
        saveError = nil
        guard let hostWindow = savePanelHostWindowProvider() else {
            let error = AnnotationImageSaveError.savePanelHostUnavailable
            saveError = error
            throw error
        }
        imageSaver.savePNG(
            image: try renderedImage(),
            attachedTo: hostWindow,
            completion: { [weak self] result in
                if case .failure(let error) = result {
                    self?.saveError = error
                }
            }
        )
    }

    public func cancel() {
        cancelTextEditing()
        isCancelled = true
    }

    func beginTextEditing(at point: CGPoint) {
        if let existing = textElement(at: point) {
            beginTextEditing(elementID: existing.id)
            return
        }

        commitTextEditing()
        document.selectElement(id: nil)
        textEditingDraft = TextEditingDraft(
            elementID: nil,
            position: point,
            displayText: "",
            style: currentTextStyle
        )
    }

    func beginTextEditing(elementID: UUID) {
        guard let element = textElement(id: elementID) else {
            return
        }
        commitTextEditing()
        document.selectElement(id: nil)
        textEditingDraft = TextEditingDraft(
            elementID: element.id,
            position: element.position,
            displayText: element.content,
            style: element.style
        )
    }

    func updateTextEditingDisplayText(_ text: String) {
        guard var draft = textEditingDraft else {
            return
        }
        draft.displayText = text
        textEditingDraft = draft
    }

    func commitTextEditing() {
        guard let draft = textEditingDraft else {
            return
        }
        textEditingDraft = nil

        let committedText = draft.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let elementID = draft.elementID {
            if committedText.isEmpty {
                document.removeElement(id: elementID)
            } else {
                document.updateTextElement(id: elementID, content: committedText)
            }
        } else if !committedText.isEmpty {
            document.add(.text(TextAnnotationElement(
                position: draft.position,
                content: committedText,
                style: draft.style
            )))
        }
    }

    func cancelTextEditing() {
        textEditingDraft = nil
    }

    private func renderedImage() throws -> CGImage {
        guard !document.elements.isEmpty else {
            return image
        }
        return try renderer.render(image: image, document: document)
    }

    private func textElement(at point: CGPoint) -> TextAnnotationElement? {
        document.elements.reversed().compactMap { element -> TextAnnotationElement? in
            guard case .text(let textElement) = element,
                  textElement.bounds.insetBy(dx: -6, dy: -6).contains(point) else {
                return nil
            }
            return textElement
        }.first
    }

    private func textElement(id: UUID) -> TextAnnotationElement? {
        document.elements.compactMap { element -> TextAnnotationElement? in
            guard case .text(let textElement) = element,
                  textElement.id == id else {
                return nil
            }
            return textElement
        }.first
    }
}

@MainActor
public final class ScreenshotSavePanelPresenter: ScreenshotSavePanelPresenting {
    public init() {}

    public static func defaultPNGName(
        timestamp: Date = Date(),
        id: UUID = UUID(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let shortID = id.uuidString.prefix(8)
        return "VoxFlow截图-\(formatter.string(from: timestamp))-\(shortID).png"
    }

    public func savePNG(
        image: CGImage,
        attachedTo hostWindow: NSWindow,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Self.defaultPNGName()
        panel.canCreateDirectories = true

        hostWindow.orderFrontRegardless()
        panel.beginSheetModal(for: hostWindow) { response in
            guard response == .OK,
                  let url = panel.url else {
                completion(.success(false))
                return
            }

            do {
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw AnnotationImageSaveError.pngEncodingFailed
                }
                try data.write(to: url, options: .atomic)
                completion(.success(true))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

public typealias SystemAnnotationImageSaver = ScreenshotSavePanelPresenter

public enum AnnotationImageSaveError: Error, Equatable {
    case pngEncodingFailed
    case savePanelHostUnavailable
}
