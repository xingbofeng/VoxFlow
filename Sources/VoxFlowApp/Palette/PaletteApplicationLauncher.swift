import AppKit

protocol PaletteApplicationLaunching: AnyObject {
    func openApplication(atPath path: String) -> Bool
}

final class WorkspacePaletteApplicationLauncher: PaletteApplicationLaunching {
    func openApplication(atPath path: String) -> Bool {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
