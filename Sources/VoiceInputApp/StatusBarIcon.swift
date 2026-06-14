import AppKit

enum StatusBarIcon {
    static let accessibilityName = ProductBrand.chineseDisplayName
    static let visibleTitle = ""
    static let imagePosition: NSControl.ImagePosition = .imageOnly
    static let tooltip: String? = nil
    static let autosaveName = "VoxFlowStatusItem"
    static let buttonIdentifier = NSUserInterfaceItemIdentifier("VoxFlowStatusBarButton")
    static let preferredLength = NSStatusItem.squareLength

    static func restoreVisibility(of statusItem: NSStatusItem) {
        statusItem.autosaveName = NSStatusItem.AutosaveName(autosaveName)
        statusItem.isVisible = true
    }

    static func makeImage(bundle: Bundle = .main) -> NSImage? {
        let image = NSImage(
            systemSymbolName: "mic.circle.fill",
            accessibilityDescription: accessibilityName
        )
            ?? NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: accessibilityName
            )
            ?? bundle.url(
                forResource: "AppIcon",
                withExtension: "icns"
            ).flatMap(NSImage.init(contentsOf:))

        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = accessibilityName
        return image
    }
}
