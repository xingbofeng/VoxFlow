// DictusApp/Views/MainTabView.swift adapted for Mashangxie.
// Root navigation container with Dictus-style tabs and full-screen recording overlay.
import Shared
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var coordinator: DictationCoordinator
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SharedKeys.hasCompletedOnboarding, store: AppGroup.preferences)
    private var hasCompletedOnboarding = false

    @StateObject private var modelManager = ModelManager()
    @State private var selectedTab = 0
    @State private var isColdStartMode = false

    private static var hasHandledURL = false

    private let tabs: [AppTab] = [
        .init(index: 0, titleKey: "tab.home", systemImage: "house.fill"),
        .init(index: 1, titleKey: "tab.services", systemImage: "cpu"),
        .init(index: 2, titleKey: "tab.settings", systemImage: "gearshape.fill"),
    ]

    var body: some View {
        ZStack {
            if isColdStartMode {
                SwipeBackOverlayView()
            } else {
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dictusBackground.ignoresSafeArea())

                VStack {
                    Spacer()
                    floatingTabBar
                        .padding(.bottom, 8)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }

            if coordinator.status != .idle && !isColdStartMode {
                RecordingView(mode: .standalone)
            }
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .fullScreenCover(isPresented: $appState.clipboardHandoffActive) {
            ClipboardDictationHandoffView(
                providerDisplayName: appState.selectedProvider.displayName
            ) {
                appState.dismissClipboardHandoff()
            }
            .id(appState.clipboardHandoffPresentationID)
            .environmentObject(appState)
        }
        .onOpenURL { url in
            // The clipboard-start URL is routed to AppState by VoxFlowiOSApp.
            // Here we only handle the AppGroupBridge cold-start URL.
            guard let host = url.host, host == "dictate" else { return }
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard queryItems.contains(where: { $0.name == "source" && $0.value == "keyboard" }) else {
                return
            }

            if !Self.hasHandledURL || !coordinator.isEngineRunning {
                isColdStartMode = true
            }
            Self.hasHandledURL = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                isColdStartMode = false
            }
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView(isComplete: $hasCompletedOnboarding)
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { isPresented in
                if !isPresented {
                    hasCompletedOnboarding = true
                }
            }
        )
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case 0:
            NavigationStack {
                HomeView(modelManager: modelManager)
            }
        case 1:
            NavigationStack {
                ModelManagerView(modelManager: modelManager)
            }
        default:
            NavigationStack {
                SettingsView()
            }
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedTab = tab.index
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 25, weight: .semibold))
                        Text(L10n.t(tab.titleKey))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab.index ? Color.dictusAccent : Color.primary)
                    .frame(width: 92, height: 60)
                    .background {
                        if selectedTab == tab.index {
                            Capsule()
                                .fill(Color(.systemGray5).opacity(0.92))
                                .matchedGeometryEffect(id: "selectedTab", in: tabAnimation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    @Namespace private var tabAnimation

}

private struct AppTab: Identifiable {
    let index: Int
    let titleKey: String
    let systemImage: String

    var id: Int { index }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(DictationCoordinator.shared)
}
