import CoreGraphics
import Foundation

// Annotation model adapted from sadopc/ScreenCapture (MIT), commit
// 081cb96b5c9f4bf72ace9187205009c92ab15f8c. VoxFlow extends the source model
// with ellipse, dot marker, numbered marker, mosaic, selection, and undo history.

public struct ScreenshotAnnotationColor: Equatable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let voxGreen = ScreenshotAnnotationColor(red: 0.10, green: 0.66, blue: 0.35)
    public static let red = ScreenshotAnnotationColor(red: 0.95, green: 0.20, blue: 0.20)
    public static let white = ScreenshotAnnotationColor(red: 1, green: 1, blue: 1)
    public static let black = ScreenshotAnnotationColor(red: 0, green: 0, blue: 0)
}

public struct ScreenshotAnnotationStyle: Equatable, Codable, Sendable {
    public var color: ScreenshotAnnotationColor
    public var lineWidth: CGFloat
    public var fillColor: ScreenshotAnnotationColor?

    public init(
        color: ScreenshotAnnotationColor = .voxGreen,
        lineWidth: CGFloat = 6,
        fillColor: ScreenshotAnnotationColor? = nil
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.fillColor = fillColor
    }

    public static let `default` = ScreenshotAnnotationStyle()
}

public struct ScreenshotAnnotationTextStyle: Equatable, Codable, Sendable {
    public var color: ScreenshotAnnotationColor
    public var fontSize: CGFloat
    public var fontName: String

    public init(
        color: ScreenshotAnnotationColor = .voxGreen,
        fontSize: CGFloat = 14,
        fontName: String = ".AppleSystemUIFont"
    ) {
        self.color = color
        self.fontSize = fontSize
        self.fontName = fontName
    }

    public static let `default` = ScreenshotAnnotationTextStyle()
}

public enum AnnotationElementKind: Equatable, Sendable {
    case pen
    case ellipse
    case rectangle
    case arrow
    case dotMarker
    case numberedMarker
    case text
    case mosaic
    case translatedOverlay
}

// Selection and resize semantics adapted from tokuhirom/ShotShot (MIT), commit
// c600d978c3ba1cce72c26e8af19e3bca155d0e15.
public enum AnnotationResizeHandle: Equatable, Sendable {
    case startPoint
    case endPoint
    case startXEndY
    case endXStartY
}

public enum AnnotationElement: Equatable, Identifiable, Sendable {
    case pen(FreehandAnnotationElement)
    case ellipse(EllipseAnnotationElement)
    case rectangle(RectangleAnnotationElement)
    case arrow(ArrowAnnotationElement)
    case dotMarker(DotMarkerAnnotationElement)
    case numberedMarker(NumberedMarkerAnnotationElement)
    case text(TextAnnotationElement)
    case mosaic(MosaicAnnotationElement)
    case translatedOverlay(TranslatedOverlayAnnotationElement)

    public var id: UUID {
        switch self {
        case .pen(let element): element.id
        case .ellipse(let element): element.id
        case .rectangle(let element): element.id
        case .arrow(let element): element.id
        case .dotMarker(let element): element.id
        case .numberedMarker(let element): element.id
        case .text(let element): element.id
        case .mosaic(let element): element.id
        case .translatedOverlay(let element): element.id
        }
    }

    public var kind: AnnotationElementKind {
        switch self {
        case .pen: .pen
        case .ellipse: .ellipse
        case .rectangle: .rectangle
        case .arrow: .arrow
        case .dotMarker: .dotMarker
        case .numberedMarker: .numberedMarker
        case .text: .text
        case .mosaic: .mosaic
        case .translatedOverlay: .translatedOverlay
        }
    }

    public var bounds: CGRect {
        switch self {
        case .pen(let element): element.bounds
        case .ellipse(let element): element.rect
        case .rectangle(let element): element.rect
        case .arrow(let element): element.bounds
        case .dotMarker(let element): element.bounds
        case .numberedMarker(let element): element.bounds
        case .text(let element): element.bounds
        case .mosaic(let element): element.bounds
        case .translatedOverlay(let element): element.bounds
        }
    }

    public func moved(by offset: CGSize) -> AnnotationElement {
        switch self {
        case .pen(var element):
            element.points = element.points.map { $0.offsetBy(dx: offset.width, dy: offset.height) }
            return .pen(element)
        case .ellipse(var element):
            element.rect = element.rect.offsetBy(dx: offset.width, dy: offset.height)
            return .ellipse(element)
        case .rectangle(var element):
            element.rect = element.rect.offsetBy(dx: offset.width, dy: offset.height)
            return .rectangle(element)
        case .arrow(var element):
            element.startPoint = element.startPoint.offsetBy(dx: offset.width, dy: offset.height)
            element.endPoint = element.endPoint.offsetBy(dx: offset.width, dy: offset.height)
            return .arrow(element)
        case .dotMarker(var element):
            element.center = element.center.offsetBy(dx: offset.width, dy: offset.height)
            return .dotMarker(element)
        case .numberedMarker(var element):
            element.center = element.center.offsetBy(dx: offset.width, dy: offset.height)
            return .numberedMarker(element)
        case .text(var element):
            element.position = element.position.offsetBy(dx: offset.width, dy: offset.height)
            return .text(element)
        case .mosaic(var element):
            element.points = element.points.map { $0.offsetBy(dx: offset.width, dy: offset.height) }
            return .mosaic(element)
        case .translatedOverlay(var element):
            element.lines = element.lines.map {
                TranslatedOverlayAnnotationElement.Line(
                    bounds: $0.bounds.offsetBy(dx: offset.width, dy: offset.height),
                    text: $0.text
                )
            }
            return .translatedOverlay(element)
        }
    }

    public func resized(handle: AnnotationResizeHandle, to point: CGPoint) -> AnnotationElement {
        switch self {
        case .pen:
            return self
        case .ellipse(var element):
            element.rect = element.rect.resized(handle: handle, to: point)
            return .ellipse(element)
        case .rectangle(var element):
            element.rect = element.rect.resized(handle: handle, to: point)
            return .rectangle(element)
        case .arrow(var element):
            switch handle {
            case .startPoint, .startXEndY:
                element.startPoint = point
            case .endPoint, .endXStartY:
                element.endPoint = point
            }
            return .arrow(element)
        case .dotMarker(var element):
            let distance = hypot(point.x - element.center.x, point.y - element.center.y)
            element.radius = max(3, distance)
            return .dotMarker(element)
        case .numberedMarker(var element):
            let distance = hypot(point.x - element.center.x, point.y - element.center.y)
            element.radius = max(6, distance)
            return .numberedMarker(element)
        case .text(var element):
            let newBounds = element.bounds.resized(handle: handle, to: point)
            element.position = newBounds.origin
            element.style.fontSize = max(10, newBounds.height / 1.3)
            return .text(element)
        case .mosaic:
            return self
        case .translatedOverlay:
            return self
        }
    }

    public func updatingStyle(_ style: ScreenshotAnnotationStyle) -> AnnotationElement {
        switch self {
        case .pen(var element):
            element.style = style
            return .pen(element)
        case .ellipse(var element):
            element.style = style
            return .ellipse(element)
        case .rectangle(var element):
            element.style = style
            return .rectangle(element)
        case .arrow(var element):
            element.style = style
            return .arrow(element)
        case .dotMarker(var element):
            element.style = style
            return .dotMarker(element)
        case .numberedMarker(var element):
            element.style = style
            return .numberedMarker(element)
        case .text(var element):
            element.style.color = style.color
            return .text(element)
        case .mosaic:
            return self
        case .translatedOverlay:
            return self
        }
    }

    public func updatingTextStyle(_ style: ScreenshotAnnotationTextStyle) -> AnnotationElement {
        switch self {
        case .text(var element):
            element.style = style
            return .text(element)
        default:
            return self
        }
    }

    public func duplicated(
        offset: CGSize,
        numberedMarkerNumber: Int? = nil
    ) -> AnnotationElement {
        switch self {
        case .pen(let element):
            return .pen(FreehandAnnotationElement(
                points: element.points.map { $0.offsetBy(dx: offset.width, dy: offset.height) },
                style: element.style
            ))
        case .ellipse(let element):
            return .ellipse(EllipseAnnotationElement(
                rect: element.rect.offsetBy(dx: offset.width, dy: offset.height),
                style: element.style
            ))
        case .rectangle(let element):
            return .rectangle(RectangleAnnotationElement(
                rect: element.rect.offsetBy(dx: offset.width, dy: offset.height),
                style: element.style
            ))
        case .arrow(let element):
            return .arrow(ArrowAnnotationElement(
                startPoint: element.startPoint.offsetBy(dx: offset.width, dy: offset.height),
                endPoint: element.endPoint.offsetBy(dx: offset.width, dy: offset.height),
                style: element.style
            ))
        case .dotMarker(let element):
            return .dotMarker(DotMarkerAnnotationElement(
                center: element.center.offsetBy(dx: offset.width, dy: offset.height),
                radius: element.radius,
                style: element.style
            ))
        case .numberedMarker(let element):
            return .numberedMarker(NumberedMarkerAnnotationElement(
                center: element.center.offsetBy(dx: offset.width, dy: offset.height),
                number: numberedMarkerNumber ?? element.number,
                radius: element.radius,
                style: element.style
            ))
        case .text(let element):
            return .text(TextAnnotationElement(
                position: element.position.offsetBy(dx: offset.width, dy: offset.height),
                content: element.content,
                style: element.style
            ))
        case .mosaic(let element):
            return .mosaic(MosaicAnnotationElement(
                points: element.points.map { $0.offsetBy(dx: offset.width, dy: offset.height) },
                brushSize: element.brushSize,
                blockSize: element.blockSize
            ))
        case .translatedOverlay(let element):
            return .translatedOverlay(TranslatedOverlayAnnotationElement(
                id: UUID(),
                lines: element.lines.map {
                    TranslatedOverlayAnnotationElement.Line(
                        bounds: $0.bounds.offsetBy(dx: offset.width, dy: offset.height),
                        text: $0.text
                    )
                },
                style: element.style
            ))
        }
    }
}

public struct FreehandAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var points: [CGPoint]
    public var style: ScreenshotAnnotationStyle

    public init(id: UUID = UUID(), points: [CGPoint], style: ScreenshotAnnotationStyle = .default) {
        self.id = id
        self.points = points
        self.style = style
    }

    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public struct EllipseAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var rect: CGRect
    public var style: ScreenshotAnnotationStyle

    public init(id: UUID = UUID(), rect: CGRect, style: ScreenshotAnnotationStyle = .default) {
        self.id = id
        self.rect = rect
        self.style = style
    }
}

public struct RectangleAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var rect: CGRect
    public var style: ScreenshotAnnotationStyle

    public init(id: UUID = UUID(), rect: CGRect, style: ScreenshotAnnotationStyle = .default) {
        self.id = id
        self.rect = rect
        self.style = style
    }
}

public struct ArrowAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var style: ScreenshotAnnotationStyle

    public init(
        id: UUID = UUID(),
        startPoint: CGPoint,
        endPoint: CGPoint,
        style: ScreenshotAnnotationStyle = .default
    ) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.style = style
    }

    public var bounds: CGRect {
        let padding = style.lineWidth * 3
        let minX = min(startPoint.x, endPoint.x) - padding
        let minY = min(startPoint.y, endPoint.y) - padding
        let maxX = max(startPoint.x, endPoint.x) + padding
        let maxY = max(startPoint.y, endPoint.y) + padding
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public struct DotMarkerAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var center: CGPoint
    public var radius: CGFloat
    public var style: ScreenshotAnnotationStyle

    public init(
        id: UUID = UUID(),
        center: CGPoint,
        radius: CGFloat = 6,
        style: ScreenshotAnnotationStyle = .default
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.style = style
    }

    public var bounds: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

public struct NumberedMarkerAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var center: CGPoint
    public var number: Int
    public var radius: CGFloat
    public var style: ScreenshotAnnotationStyle

    public init(
        id: UUID = UUID(),
        center: CGPoint,
        number: Int,
        radius: CGFloat = 9,
        style: ScreenshotAnnotationStyle = .default
    ) {
        self.id = id
        self.center = center
        self.number = number
        self.radius = radius
        self.style = style
    }

    public var bounds: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

public struct TextAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var position: CGPoint
    public var content: String
    public var style: ScreenshotAnnotationTextStyle

    public init(
        id: UUID = UUID(),
        position: CGPoint,
        content: String,
        style: ScreenshotAnnotationTextStyle = .default
    ) {
        self.id = id
        self.position = position
        self.content = content
        self.style = style
    }

    public var bounds: CGRect {
        let width = max(CGFloat(content.count) * style.fontSize * 0.6, style.fontSize * 2)
        return CGRect(
            x: position.x,
            y: position.y,
            width: width,
            height: style.fontSize * 1.3
        )
    }
}

public struct MosaicAnnotationElement: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var points: [CGPoint]
    public var brushSize: CGFloat
    public var blockSize: CGFloat

    public init(
        id: UUID = UUID(),
        points: [CGPoint],
        brushSize: CGFloat = 18,
        blockSize: CGFloat = 8
    ) {
        self.id = id
        self.points = points
        self.brushSize = brushSize
        self.blockSize = blockSize
    }

    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        let padding = brushSize / 2
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + brushSize,
            height: maxY - minY + brushSize
        )
    }
}

/// 译文覆盖元素：把每行译文画在原文 bbox 位置上，覆盖原文。
/// bounds 用 image 像素坐标，top-left origin（跟 OCR 输出一致）。
public struct TranslatedOverlayAnnotationElement: Equatable, Identifiable, Sendable {
    public struct Line: Equatable, Sendable {
        public var bounds: CGRect
        public var text: String

        public init(bounds: CGRect, text: String) {
            self.bounds = bounds
            self.text = text
        }
    }

    public let id: UUID
    public var lines: [Line]
    public var style: ScreenshotAnnotationTextStyle

    public init(
        id: UUID = UUID(),
        lines: [Line],
        style: ScreenshotAnnotationTextStyle = .default
    ) {
        self.id = id
        self.lines = lines
        self.style = style
    }

    public var bounds: CGRect {
        guard let first = lines.first else { return .zero }
        var union = first.bounds
        for line in lines.dropFirst() {
            union = union.union(line.bounds)
        }
        return union
    }
}

public struct AnnotationDocument: Equatable, Sendable {
    public private(set) var elements: [AnnotationElement]
    public private(set) var selectedElementIDs: [UUID]
    public var selectedElementID: UUID? { selectedElementIDs.last }
    private var undoStack: [Snapshot]
    private var redoStack: [Snapshot]

    public init(elements: [AnnotationElement] = []) {
        self.elements = elements
        self.selectedElementIDs = []
        self.undoStack = []
        self.redoStack = []
    }

    public mutating func add(_ element: AnnotationElement) {
        saveUndoSnapshot()
        elements.append(element)
        selectedElementIDs = [element.id]
    }

    public mutating func add(contentsOf newElements: [AnnotationElement]) {
        guard !newElements.isEmpty else { return }
        saveUndoSnapshot()
        elements.append(contentsOf: newElements)
        selectedElementIDs = newElements.map(\.id)
    }

    public mutating func replaceTranslatedOverlay(with element: TranslatedOverlayAnnotationElement) {
        let nextElement = AnnotationElement.translatedOverlay(element)
        let nextElements = elements.filter { $0.kind != .translatedOverlay } + [nextElement]
        guard nextElements != elements || selectedElementIDs != [element.id] else { return }
        saveUndoSnapshot()
        elements = nextElements
        selectedElementIDs = [element.id]
    }

    public mutating func removeElement(id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        saveUndoSnapshot()
        elements.removeAll { $0.id == id }
        selectedElementIDs.removeAll { $0 == id }
    }

    public mutating func updateTextElement(id: UUID, content: String) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              case .text(var element) = elements[index] else {
            return
        }
        saveUndoSnapshot()
        element.content = content
        elements[index] = .text(element)
        selectedElementIDs = [id]
    }

    public mutating func clear() {
        guard !elements.isEmpty || !selectedElementIDs.isEmpty else { return }
        saveUndoSnapshot()
        elements.removeAll()
        selectedElementIDs = []
    }

    public mutating func selectElement(id: UUID?) {
        guard id == nil || elements.contains(where: { $0.id == id }) else { return }
        selectedElementIDs = id.map { [$0] } ?? []
    }

    public mutating func toggleElementSelection(id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        if selectedElementIDs.contains(id) {
            selectedElementIDs.removeAll { $0 == id }
        } else {
            selectedElementIDs.append(id)
        }
    }

    public mutating func selectElements(
        intersecting rect: CGRect,
        extendingSelection: Bool = false
    ) {
        let normalizedRect = CGRect(
            x: min(rect.minX, rect.maxX),
            y: min(rect.minY, rect.maxY),
            width: abs(rect.width),
            height: abs(rect.height)
        )
        let hitIDs = elements
            .filter { $0.bounds.intersects(normalizedRect) }
            .map(\.id)

        if extendingSelection {
            for id in hitIDs where !selectedElementIDs.contains(id) {
                selectedElementIDs.append(id)
            }
        } else {
            selectedElementIDs = hitIDs
        }
    }

    public mutating func beginUndoGroup() {
        saveUndoSnapshot()
    }

    public mutating func moveSelectedElement(by offset: CGSize, recordsUndo: Bool = true) {
        guard !selectedElementIDs.isEmpty else {
            return
        }
        if recordsUndo {
            saveUndoSnapshot()
        }
        for selectedElementID in selectedElementIDs {
            guard let index = elements.firstIndex(where: { $0.id == selectedElementID }) else {
                continue
            }
            elements[index] = elements[index].moved(by: offset)
        }
    }

    public mutating func resizeSelectedElement(
        handle: AnnotationResizeHandle,
        to point: CGPoint,
        recordsUndo: Bool = true
    ) {
        guard let selectedElementID,
              let index = elements.firstIndex(where: { $0.id == selectedElementID }) else {
            return
        }
        if recordsUndo {
            saveUndoSnapshot()
        }
        elements[index] = elements[index].resized(handle: handle, to: point)
    }

    public mutating func updateSelectedStyle(_ style: ScreenshotAnnotationStyle) {
        let updates = selectedElementIDs.compactMap { selectedElementID -> (Int, AnnotationElement)? in
            guard let index = elements.firstIndex(where: { $0.id == selectedElementID }) else {
                return nil
            }
            let updated = elements[index].updatingStyle(style)
            guard updated != elements[index] else {
                return nil
            }
            return (index, updated)
        }
        guard !updates.isEmpty else {
            return
        }
        saveUndoSnapshot()
        for (index, updated) in updates {
            elements[index] = updated
        }
    }

    public mutating func updateSelectedTextStyle(_ style: ScreenshotAnnotationTextStyle) {
        let updates = selectedElementIDs.compactMap { selectedElementID -> (Int, AnnotationElement)? in
            guard let index = elements.firstIndex(where: { $0.id == selectedElementID }) else {
                return nil
            }
            let updated = elements[index].updatingTextStyle(style)
            guard updated != elements[index] else {
                return nil
            }
            return (index, updated)
        }
        guard !updates.isEmpty else {
            return
        }
        saveUndoSnapshot()
        for (index, updated) in updates {
            elements[index] = updated
        }
    }

    public mutating func updateSelectedTextFontSize(_ fontSize: CGFloat) {
        let updates = selectedElementIDs.compactMap { selectedElementID -> (Int, AnnotationElement)? in
            guard let index = elements.firstIndex(where: { $0.id == selectedElementID }),
                  case .text(var element) = elements[index],
                  element.style.fontSize != fontSize else {
                return nil
            }
            element.style.fontSize = fontSize
            return (index, .text(element))
        }
        guard !updates.isEmpty else {
            return
        }
        saveUndoSnapshot()
        for (index, updated) in updates {
            elements[index] = updated
        }
    }

    public mutating func deleteSelectedElement() {
        guard !selectedElementIDs.isEmpty else { return }
        let idsToDelete = Set(selectedElementIDs)
        saveUndoSnapshot()
        elements.removeAll { idsToDelete.contains($0.id) }
        selectedElementIDs = []
    }

    public func hitTestElement(at point: CGPoint) -> UUID? {
        elements.reversed().first { elementContainsPoint($0, point) }?.id
    }

    public mutating func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    public mutating func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    private var currentSnapshot: Snapshot {
        Snapshot(elements: elements, selectedElementIDs: selectedElementIDs)
    }

    private mutating func saveUndoSnapshot() {
        undoStack.append(currentSnapshot)
        redoStack.removeAll()
    }

    private mutating func restore(_ snapshot: Snapshot) {
        elements = snapshot.elements
        selectedElementIDs = snapshot.selectedElementIDs
    }
}

private struct Snapshot: Equatable, Sendable {
    var elements: [AnnotationElement]
    var selectedElementIDs: [UUID]
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}

private extension CGRect {
    func resized(handle: AnnotationResizeHandle, to point: CGPoint) -> CGRect {
        let start = origin
        let end = CGPoint(x: maxX, y: maxY)
        let newStart: CGPoint
        let newEnd: CGPoint

        switch handle {
        case .startPoint:
            newStart = point
            newEnd = end
        case .endPoint:
            newStart = start
            newEnd = point
        case .startXEndY:
            newStart = CGPoint(x: point.x, y: start.y)
            newEnd = CGPoint(x: end.x, y: point.y)
        case .endXStartY:
            newStart = CGPoint(x: start.x, y: point.y)
            newEnd = CGPoint(x: point.x, y: end.y)
        }

        return CGRect(
            x: min(newStart.x, newEnd.x),
            y: min(newStart.y, newEnd.y),
            width: abs(newEnd.x - newStart.x),
            height: abs(newEnd.y - newStart.y)
        )
    }
}

private func elementContainsPoint(_ element: AnnotationElement, _ point: CGPoint) -> Bool {
    switch element {
    case .pen(let element):
        return polylineContainsPoint(element.points, point, tolerance: max(10, element.style.lineWidth * 3))
    case .arrow(let element):
        return segmentContainsPoint(
            start: element.startPoint,
            end: element.endPoint,
            point: point,
            tolerance: max(12, element.style.lineWidth * 3)
        )
    case .rectangle(let element):
        return element.rect.insetBy(dx: -10, dy: -10).contains(point)
    case .ellipse(let element):
        return element.rect.insetBy(dx: -10, dy: -10).contains(point)
    case .dotMarker(let element):
        return element.bounds.insetBy(dx: -8, dy: -8).contains(point)
    case .numberedMarker(let element):
        return element.bounds.insetBy(dx: -8, dy: -8).contains(point)
    case .text(let element):
        return element.bounds.insetBy(dx: -12, dy: -12).contains(point)
    case .mosaic(let element):
        if element.points.count == 1, let center = element.points.first {
            return hypot(point.x - center.x, point.y - center.y) <= max(10, element.brushSize / 2 + 4)
        }
        return polylineContainsPoint(element.points, point, tolerance: max(10, element.brushSize / 2 + 4))
    case .translatedOverlay(let element):
        return element.lines.contains { $0.bounds.insetBy(dx: -4, dy: -4).contains(point) }
    }
}

private func polylineContainsPoint(_ points: [CGPoint], _ point: CGPoint, tolerance: CGFloat) -> Bool {
    guard points.count >= 2 else { return false }
    return zip(points, points.dropFirst()).contains { start, end in
        segmentContainsPoint(start: start, end: end, point: point, tolerance: tolerance)
    }
}

private func segmentContainsPoint(start: CGPoint, end: CGPoint, point: CGPoint, tolerance: CGFloat) -> Bool {
    let lineLength = hypot(end.x - start.x, end.y - start.y)
    guard lineLength > 0 else { return false }

    let t = max(0, min(1, (
        (point.x - start.x) * (end.x - start.x) +
        (point.y - start.y) * (end.y - start.y)
    ) / (lineLength * lineLength)))
    let nearest = CGPoint(
        x: start.x + t * (end.x - start.x),
        y: start.y + t * (end.y - start.y)
    )
    return hypot(point.x - nearest.x, point.y - nearest.y) <= tolerance
}
