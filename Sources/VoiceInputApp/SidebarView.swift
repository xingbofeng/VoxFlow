import SwiftUI

struct SidebarView: View {
    @Binding var selectedRoute: NavigationRoute

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(NavigationRoute.allCases) { route in
                    sidebarItem(route)
                }
            }
            .padding(10)
        }
        .background(AppTheme.ColorToken.sidebarBackground)
    }

    private func sidebarItem(_ route: NavigationRoute) -> some View {
        let isSelected = selectedRoute == route
        return Button {
            selectedRoute = route
        } label: {
            HStack(spacing: 10) {
                Image(systemName: route.systemImage)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected
                            ? AppTheme.ColorToken.accent
                            : AppTheme.ColorToken.sidebarText
                    )
                    .frame(width: 22)
                Text(route.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? AppTheme.ColorToken.primaryText
                            : AppTheme.ColorToken.sidebarText
                    )
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AppTheme.ColorToken.selectionBackground
                    : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(
                        isSelected
                            ? AppTheme.ColorToken.selectionBorder
                            : Color.clear,
                        lineWidth: AppTheme.Border.selectedLineWidth
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(AppTheme.ColorToken.accent)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
