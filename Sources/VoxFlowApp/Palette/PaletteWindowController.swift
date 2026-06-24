import AppKit
import SwiftUI

private final class PalettePanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PaletteWindowController: NSWindowController {
    private let viewModel: PaletteViewModel
    private let actionService: AssetActionService
    private let onCommand: (PaletteCommand) -> Void
    private var previousTarget: DictationTarget?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?

    var isVisible: Bool {
        window?.isVisible == true
    }

    init(
        repository: any AssetRepository,
        actionService: AssetActionService,
        onCommand: @escaping (PaletteCommand) -> Void
    ) {
        let viewModel = PaletteViewModel(
            repository: repository,
            actionService: actionService
        )
        self.viewModel = viewModel
        self.actionService = actionService
        self.onCommand = onCommand

        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 470),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.center()

        super.init(window: panel)

        panel.contentView = NSHostingView(
            rootView: PaletteView(
                viewModel: viewModel,
                onCommand: onCommand,
                onDefaultAction: { defaultAction in
                    if case let .openURL(urlString) = defaultAction,
                       let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                },
                onAssetAction: { [weak self] action, asset in
                    Task { @MainActor in
                        await self?.performAssetAction(action, on: asset)
                    }
                }
            )
        )
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        previousTarget = NSWorkspace.shared.frontmostApplication.map(Self.dictationTarget)
        viewModel.goBack()
        installKeyMonitors()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    override func close() {
        removeKeyMonitors()
        super.close()
    }

    func dismissOrGoBack() {
        if viewModel.mode == .home {
            close()
        } else {
            viewModel.goBack()
        }
    }

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            if viewModel.isActionPanelPresented {
                viewModel.dismissActionPanel()
                return true
            }
            dismissOrGoBack()
            return true
        }

        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "p" {
            viewModel.toggleTypeFilter()
            return true
        }
        if modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "k" {
            viewModel.toggleActionPanel()
            return true
        }

        if viewModel.isActionPanelPresented {
            if let shortcutAction = actionPanelShortcutAction(for: event, modifierFlags: modifierFlags) {
                performSelectedAssetAction(shortcutAction)
                return true
            }
            switch event.keyCode {
            case 125:
                viewModel.moveActionSelectionDown()
                return true
            case 126:
                viewModel.moveActionSelectionUp()
                return true
            case 36, 76:
                let shortcutAction: AssetAction?
                if modifierFlags.contains(.command) {
                    shortcutAction = .copy
                } else if modifierFlags.contains(.option) {
                    shortcutAction = .pasteAndKeepOpen
                } else {
                    shortcutAction = viewModel.selectedActionPanelAction()
                }
                performSelectedAssetAction(shortcutAction)
                return true
            default:
                return false
            }
        }

        switch event.keyCode {
        case 125:
            viewModel.moveSelectionDown()
            return true
        case 126:
            viewModel.moveSelectionUp()
            return true
        case 36, 76:
            performPrimaryKeyboardAction()
            return true
        default:
            return false
        }
    }

    private func performPrimaryKeyboardAction() {
        switch viewModel.primaryKeyboardAction() {
        case .none:
            break
        case let .activateCommand(command):
            do {
                try viewModel.activate(command)
            } catch {
                onCommand(command)
            }
        case let .performAssetAction(defaultAction, assetID):
            guard let asset = viewModel.assets.first(where: { $0.id == assetID }) else {
                return
            }
            switch defaultAction {
            case let .openURL(urlString):
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            case let .assetAction(action):
                Task { @MainActor in
                    await performAssetAction(action, on: asset)
                }
            }
        }
    }

    private func performSelectedAssetAction(_ action: AssetAction?) {
        guard let action, let asset = viewModel.selectedAsset else { return }
        Task { @MainActor in
            await performAssetAction(action, on: asset)
        }
    }

    private func actionPanelShortcutAction(
        for event: NSEvent,
        modifierFlags: NSEvent.ModifierFlags
    ) -> AssetAction? {
        if event.keyCode == 36 || event.keyCode == 76 {
            if modifierFlags.contains(.command) {
                return .copy
            }
            if modifierFlags.contains(.option) {
                return .pasteAndKeepOpen
            }
            return nil
        }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifierFlags.contains(.command), key == "y" {
            return .quickLook
        }
        if modifierFlags.contains(.command), modifierFlags.contains(.shift), key == "s" {
            return .saveAsFile
        }
        if modifierFlags.contains(.control), key == "x" {
            return .delete
        }
        return nil
    }

    private func performAssetAction(_ action: AssetAction, on asset: AssetItem) async {
        let keepsOpen = action == .pasteAndKeepOpen
        let shouldRestorePalette = keepsOpen && isVisible
        if action.requiresOriginalApplication {
            temporarilyHideForOriginalTargetAction()
            await DictationTargetActivation.activate(previousTarget)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        _ = try? await actionService.perform(action, on: asset)
        if action == .delete {
            try? viewModel.reloadAssets()
        }
        viewModel.dismissActionPanel()
        if action.closesPaletteAfterAction, !keepsOpen {
            close()
        } else if shouldRestorePalette {
            window?.orderFrontRegardless()
            window?.makeKey()
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isVisible == true else { return event }
            return self?.handleKeyDown(event) == true ? nil : event
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard self?.isVisible == true else { return event }
            self?.closeWhenClickingOutside(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard self?.isVisible == true else { return }
                _ = self?.handleKeyDown(event)
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.closeWhenClickingOutside(event)
            }
        }
    }

    private func removeKeyMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func temporarilyHideForOriginalTargetAction() {
        window?.orderOut(nil)
    }

    private func closeWhenClickingOutside(_ event: NSEvent) {
        guard isVisible, let window else { return }
        guard !window.frame.contains(NSEvent.mouseLocation) else { return }
        close()
    }

    private static func dictationTarget(for application: NSRunningApplication) -> DictationTarget {
        DictationTarget(
            bundleID: application.bundleIdentifier,
            appName: application.localizedName,
            pid: Int(application.processIdentifier)
        )
    }
}

private extension AssetAction {
    var requiresOriginalApplication: Bool {
        switch self {
        case .paste, .pasteAndKeepOpen, .pasteOCRText, .pasteFile, .pasteFilePath:
            return true
        default:
            return false
        }
    }

    var closesPaletteAfterAction: Bool {
        switch self {
        case .paste, .pasteOCRText, .pasteFile, .pasteFilePath, .delete:
            return true
        default:
            return false
        }
    }
}
