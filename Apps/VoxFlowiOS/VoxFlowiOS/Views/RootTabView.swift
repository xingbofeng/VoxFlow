import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            DictationView()
                .tabItem {
                    Label(L10n.t("tab.dictation"), systemImage: "mic.fill")
                }
                .tag(0)

            DiagnosticsView()
                .tabItem {
                    Label(L10n.t("tab.diagnostics"), systemImage: "stethoscope")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label(L10n.t("tab.settings"), systemImage: "gearshape.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppState())
}
