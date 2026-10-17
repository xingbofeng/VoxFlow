import SwiftUI

struct SidebarView: View {
    @Binding var selectedRoute: NavigationRoute

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(NavigationRoute.allCases) { route in
                    sidebarItem(route)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .background(AppTheme.ColorToken.sidebarBackground)

    }

    private func sidebarItem(_ route: NavigationRoute) -> some View {
        let isSelected = selectedRoute == route
        return Button {
            selectedRoute = route
        } label: {
            HStack(spacing: 9) {
                Image(systemName: route.systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(
                        isSelected
                            ? AppTheme.ColorToken.primaryText
                            : AppTheme.ColorToken.secondaryText
                    )
                    .frame(width: 20)
                Text(route.title)
                    .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(
                        isSelected
                            ? AppTheme.ColorToken.primaryText
                            : AppTheme.ColorToken.sidebarText
                    )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CDS.Radius.lg, style: .continuous)
                    .fill(isSelected ? AppTheme.ColorToken.selectionBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CDS.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.ColorToken.selectionBorder : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CDSGhostButtonStyle(cornerRadius: CDS.Radius.lg))
    }
}
