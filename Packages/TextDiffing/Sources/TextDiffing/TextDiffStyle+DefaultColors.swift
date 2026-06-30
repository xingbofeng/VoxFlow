#if os(macOS)
import AppKit

extension NSColor {
    static let diffBackgroundInsert = NSColor(red: 0.878, green: 0.965, blue: 0.878, alpha: 1)
    static let diffBackgroundRemove = NSColor(red: 0.985, green: 0.890, blue: 0.890, alpha: 1)
}
#elseif os(iOS)
import UIKit

extension UIColor {
    static let diffBackgroundInsert = UIColor(red: 0.878, green: 0.965, blue: 0.878, alpha: 1)
    static let diffBackgroundRemove = UIColor(red: 0.985, green: 0.890, blue: 0.890, alpha: 1)
}
#endif
