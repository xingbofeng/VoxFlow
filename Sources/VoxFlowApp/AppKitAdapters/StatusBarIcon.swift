import AppKit

enum StatusBarIcon {
    static let accessibilityName = ProductBrand.chineseDisplayName
    static let visibleTitle = ""
    static let imagePosition: NSControl.ImagePosition = .imageOnly
    static let tooltip: String? = nil
    static let autosaveName = "VoxFlowStatusItem"
    static let buttonIdentifier = NSUserInterfaceItemIdentifier("VoxFlowStatusBarButton")
    static let preferredLength = NSStatusItem.squareLength
    static let persistedAutosaveNames = [
        autosaveName,
        "VoxFlowStatusItem",
        "VoxFlowStatusItemV2",
        "VoxFlowStatusItemRuntime",
        "VoxFlowStatusItemVisibleV3",
        "Item-0",
        "Item-1",
    ]
    static let placementResetMarkerKey = "VoxFlowStatusItemPlacementResetV1"
    static let persistedBundleIdentifiers = [
        ProductBrand.bundleIdentifier,
        ProductBrand.legacyBundleIdentifier,
    ]

    @MainActor
    static func restoreVisibility(of statusItem: NSStatusItem) {
        statusItem.autosaveName = NSStatusItem.AutosaveName(autosaveName)
        statusItem.isVisible = true
    }

    @MainActor
    @discardableResult
    static func configure(_ statusItem: NSStatusItem, usesGrayIcon: Bool = false) -> Bool {
        restoreVisibility(of: statusItem)
        statusItem.length = preferredLength
        guard let button = statusItem.button else { return false }
        button.identifier = buttonIdentifier
        button.image = makeImage()
        button.title = visibleTitle
        button.imagePosition = imagePosition
        button.toolTip = tooltip
        button.contentTintColor = usesGrayIcon ? .secondaryLabelColor : nil
        button.setAccessibilityLabel(accessibilityName)
        return true
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

    static func clearPersistedVisibilityState(
        bundleIdentifiers: [String] = persistedBundleIdentifiers,
        defaultsFactory: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) {
        for bundleIdentifier in bundleIdentifiers {
            let defaults: UserDefaults?
            if bundleIdentifier == ProductBrand.bundleIdentifier {
                defaults = .standard
            } else {
                defaults = defaultsFactory(bundleIdentifier)
            }
            guard let defaults else { continue }
            clearPersistedVisibilityState(from: defaults)
        }
    }

    private static func clearPersistedVisibilityState(from defaults: UserDefaults) {
        for autosaveName in persistedAutosaveNames {
            defaults.removeObject(forKey: "NSStatusItem Preferred Position \(autosaveName)")
            defaults.removeObject(forKey: "NSStatusItem Visible \(autosaveName)")
            defaults.removeObject(forKey: "NSStatusItem VisibleCC \(autosaveName)")
        }
        defaults.removeObject(forKey: placementResetMarkerKey)
        defaults.synchronize()
    }
}
