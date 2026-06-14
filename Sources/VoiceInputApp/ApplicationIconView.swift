import AppKit
import SwiftUI

struct ApplicationIconView: View {
    let name: String
    let iconPath: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let iconPath,
               let image = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.ColorToken.controlBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "A"
    }
}
