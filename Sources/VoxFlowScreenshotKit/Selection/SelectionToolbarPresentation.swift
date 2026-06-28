import CoreGraphics

public enum SelectionToolbarRole: CaseIterable, Equatable, Sendable {
    case select
    case pen
    case circle
    case rectangle
    case arrow
    case dotMarker
    case numberedMarker
    case text
    case mosaic
    case scrollCapture
    case textRecognition
    case translate
    case screenRecording
    case color
    case lineWidth
    case fontSize
    case download
    case copy
    case paste
    case duplicate
    case undo
    case redo
    case cancel
    case complete
}

public struct SelectionToolbarItem: Equatable, Sendable {
    public let role: SelectionToolbarRole
    public let systemImageName: String
    public let tooltip: String
}

public struct SelectionToolbarPresentation: Equatable, Sendable {
    public let items: [SelectionToolbarItem]
    public let itemSize: CGFloat
    public let itemSpacing: CGFloat
    public let contentPadding: CGFloat

    public static let `default` = SelectionToolbarPresentation(
        items: [
            SelectionToolbarItem(role: .select, systemImageName: "cursorarrow", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.select),
            SelectionToolbarItem(role: .pen, systemImageName: "pencil.tip", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.pen),
            SelectionToolbarItem(role: .circle, systemImageName: "circle", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.circle),
            SelectionToolbarItem(role: .rectangle, systemImageName: "rectangle", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.rectangle),
            SelectionToolbarItem(role: .arrow, systemImageName: "arrow.up.right", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.arrow),
            SelectionToolbarItem(role: .dotMarker, systemImageName: "smallcircle.filled.circle", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.pointMarker),
            SelectionToolbarItem(role: .numberedMarker, systemImageName: "1.circle", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.numberedMarker),
            SelectionToolbarItem(role: .text, systemImageName: "t.square", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.text),
            SelectionToolbarItem(role: .mosaic, systemImageName: "checkerboard.rectangle", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.mosaic),
            SelectionToolbarItem(role: .scrollCapture, systemImageName: "arrow.up.and.down.text.horizontal", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.scrollCapture),
            SelectionToolbarItem(role: .textRecognition, systemImageName: "text.viewfinder", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.textRecognition),
            SelectionToolbarItem(role: .translate, systemImageName: "character.bubble", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.translate),
            SelectionToolbarItem(role: .screenRecording, systemImageName: "record.circle", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.screenRecording),
            SelectionToolbarItem(role: .color, systemImageName: "paintpalette", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.color),
            SelectionToolbarItem(role: .lineWidth, systemImageName: "lineweight", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.lineWidth),
            SelectionToolbarItem(role: .fontSize, systemImageName: "textformat.size", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.fontSize),
            SelectionToolbarItem(role: .copy, systemImageName: "doc.on.doc", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.copy),
            SelectionToolbarItem(role: .paste, systemImageName: "doc.on.clipboard", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.paste),
            SelectionToolbarItem(role: .duplicate, systemImageName: "plus.square.on.square", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.duplicate),
            SelectionToolbarItem(role: .undo, systemImageName: "arrow.uturn.backward", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.undo),
            SelectionToolbarItem(role: .redo, systemImageName: "arrow.uturn.forward", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.redo),
            SelectionToolbarItem(role: .download, systemImageName: "square.and.arrow.down", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.download),
            SelectionToolbarItem(role: .cancel, systemImageName: "xmark", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.cancel),
            SelectionToolbarItem(role: .complete, systemImageName: "checkmark", tooltip: ScreenshotL10n.ScreenshotKit.Toolbar.complete),
        ]
    )

    public init(
        items: [SelectionToolbarItem],
        itemSize: CGFloat = 28,
        itemSpacing: CGFloat = 4,
        contentPadding: CGFloat = 8
    ) {
        self.items = items
        self.itemSize = itemSize
        self.itemSpacing = itemSpacing
        self.contentPadding = contentPadding
    }

    public var size: CGSize {
        let itemWidth = CGFloat(items.count) * itemSize
        let spacingWidth = CGFloat(max(0, items.count - 1)) * itemSpacing
        let padding = contentPadding * 2
        return CGSize(
            width: itemWidth + spacingWidth + padding,
            height: itemSize + padding
        )
    }

    public func toolbarFrame(
        for selectionRect: CGRect,
        visibleBounds: CGRect
    ) -> CGRect {
        let toolbarSize = size
        let proposedX = selectionRect.midX - toolbarSize.width / 2
        let x = min(
            max(proposedX, visibleBounds.minX + contentPadding),
            visibleBounds.maxX - toolbarSize.width - contentPadding
        )
        let belowY = selectionRect.maxY + contentPadding
        let y: CGFloat
        if belowY + toolbarSize.height <= visibleBounds.maxY {
            y = belowY
        } else {
            y = max(
                visibleBounds.minY + contentPadding,
                selectionRect.minY - toolbarSize.height - contentPadding
            )
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }
}
