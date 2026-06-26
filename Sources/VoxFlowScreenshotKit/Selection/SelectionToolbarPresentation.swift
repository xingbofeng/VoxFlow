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
            SelectionToolbarItem(role: .select, systemImageName: "cursorarrow", tooltip: "选择"),
            SelectionToolbarItem(role: .pen, systemImageName: "pencil.tip", tooltip: "画笔"),
            SelectionToolbarItem(role: .circle, systemImageName: "circle", tooltip: "圈注"),
            SelectionToolbarItem(role: .rectangle, systemImageName: "rectangle", tooltip: "矩形"),
            SelectionToolbarItem(role: .arrow, systemImageName: "arrow.up.right", tooltip: "箭头"),
            SelectionToolbarItem(role: .dotMarker, systemImageName: "smallcircle.filled.circle", tooltip: "标记点"),
            SelectionToolbarItem(role: .numberedMarker, systemImageName: "1.circle", tooltip: "数字点"),
            SelectionToolbarItem(role: .text, systemImageName: "t.square", tooltip: "文字"),
            SelectionToolbarItem(role: .mosaic, systemImageName: "checkerboard.rectangle", tooltip: "马赛克"),
            SelectionToolbarItem(role: .scrollCapture, systemImageName: "arrow.up.and.down.text.horizontal", tooltip: "滚动长图"),
            SelectionToolbarItem(role: .textRecognition, systemImageName: "text.viewfinder", tooltip: "文字识别"),
            SelectionToolbarItem(role: .translate, systemImageName: "character.bubble", tooltip: "翻译"),
            SelectionToolbarItem(role: .screenRecording, systemImageName: "record.circle", tooltip: "区域录屏"),
            SelectionToolbarItem(role: .color, systemImageName: "paintpalette", tooltip: "颜色"),
            SelectionToolbarItem(role: .lineWidth, systemImageName: "lineweight", tooltip: "线宽"),
            SelectionToolbarItem(role: .fontSize, systemImageName: "textformat.size", tooltip: "字号"),
            SelectionToolbarItem(role: .copy, systemImageName: "doc.on.doc", tooltip: "复制"),
            SelectionToolbarItem(role: .paste, systemImageName: "doc.on.clipboard", tooltip: "粘贴"),
            SelectionToolbarItem(role: .duplicate, systemImageName: "plus.square.on.square", tooltip: "复制一份"),
            SelectionToolbarItem(role: .undo, systemImageName: "arrow.uturn.backward", tooltip: "撤销"),
            SelectionToolbarItem(role: .redo, systemImageName: "arrow.uturn.forward", tooltip: "重做"),
            SelectionToolbarItem(role: .download, systemImageName: "square.and.arrow.down", tooltip: "下载"),
            SelectionToolbarItem(role: .cancel, systemImageName: "xmark", tooltip: "取消"),
            SelectionToolbarItem(role: .complete, systemImageName: "checkmark", tooltip: "完成"),
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
