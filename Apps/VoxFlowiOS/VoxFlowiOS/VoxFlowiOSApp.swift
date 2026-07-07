import SwiftUI

@main
struct VoxFlowiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var dictationCoordinator = DictationCoordinator.shared

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(appState)
                .environmentObject(dictationCoordinator)
                .onOpenURL { url in
                    // ClipboardBridge deep link: present the handoff page.
                    // Routed BEFORE the coordinator so it doesn't fall through
                    // to the AppGroupBridge startFromKeyboardRequest path.
                    if url.scheme == "mashangxie",
                       url.host == "clipboard-start"
                           || (url.host == "dictation" && url.path == "/clipboard-start") {
                        appState.presentClipboardHandoff()
                        return
                    }
                    dictationCoordinator.handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dictationCoordinator.prepareForBackground()
                    }
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if ProcessInfo.processInfo.arguments.contains("--mashangxie-ui-test-keyboard-host") {
            UITestKeyboardHostView()
        } else {
            MainTabView()
        }
    }
}
