import SwiftUI

struct InstalledAppSelectorView: View {
    let installedApps: [InstalledApplication]
    let selectedBundleIDs: Set<String>
    let onSelect: (InstalledApplication) -> Void
    let onRemove: (String) -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextField(L10n.localize("installed_app_selector.search_placeholder", comment: "Installed app search placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.ColorToken.controlBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredApps) { app in
                        appRow(app)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private var filteredApps: [InstalledApplication] {
        guard !searchText.isEmpty else { return installedApps }
        let query = searchText.lowercased()
        return installedApps.filter { app in
            app.name.lowercased().contains(query)
                || (app.bundleID?.lowercased().contains(query) ?? false)
        }
    }

    private func appRow(_ app: InstalledApplication) -> some View {
        let isSelected = app.bundleID.map { selectedBundleIDs.contains($0) } ?? false

        return HStack(spacing: 10) {
            ApplicationIconView(name: app.name, iconPath: app.iconPath, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                if let bundleID = app.bundleID {
                    Text(bundleID)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if isSelected {
                Button {
                    if let bundleID = app.bundleID {
                        onRemove(bundleID)
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    onSelect(app)
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
    }
}
