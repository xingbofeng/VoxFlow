import AppKit
import SwiftUI

struct MainShellView: View {
    @State private var selectedRoute: NavigationRoute = .home
    @State private var isSidebarVisible = true
    @State private var applicationPointerMonitor: Any?
    @ObservedObject var viewModel: WorkbenchViewModel
    @ObservedObject var homeViewModel: HomeDashboardViewModel
    @ObservedObject var voiceCorrectionViewModel: VoiceCorrectionViewModel
    @ObservedObject var styleViewModel: StyleViewModel
    @ObservedObject var llmProviderViewModel: LLMProviderViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var fileTranscriptionViewModel: FileTranscriptionViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject var screenshotRecordViewModel: ScreenshotRecordViewModel
    @ObservedObject var navigationRouter: WorkbenchNavigationRouter
    @ObservedObject var updatePromptStore: UpdatePromptPresentationStore
    let onCheckForUpdates: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    VStack(spacing: 0) {
                        sidebarToggle(alignment: .leading)
                        Divider()
                        SidebarView(selectedRoute: $selectedRoute)
                    }
                        .frame(minWidth: 220, idealWidth: 220, maxWidth: 220)
                        .layoutPriority(1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                    detailView
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            sidebarToggle(alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: 56, idealWidth: 56, maxWidth: 56)
                        .frame(maxHeight: .infinity)
                        .background(AppTheme.ColorToken.sidebarBackground)
                        Divider()
                        detailView
                    }
                }
            }

            if let detail = homeViewModel.selectedHomeDetail {
                HomeDetailOverlay(viewModel: homeViewModel, detail: detail)
            }

            if let updatePrompt = updatePromptStore.presentation {
                UpdatePromptOverlayView(presentation: updatePrompt) { action in
                    updatePromptStore.finish(action)
                }
            }
        }
        .frame(minWidth: 1_260, minHeight: 720)
        .tint(AppTheme.ColorToken.accent)
        .preferredColorScheme(settingsViewModel.systemOption(.darkMode) ? .dark : .light)
        .onAppear {
            viewModel.loadIfNeeded()
            updatePromptStore.isHostVisible = true
            installApplicationPointerMonitor()
        }
        .onDisappear {
            updatePromptStore.isHostVisible = false
            updatePromptStore.finish(.remindNextTime)
            removeApplicationPointerMonitor()
        }
        .onReceive(homeViewModel.openHistoryDetailRequests) { id in
            selectedRoute = .home
            homeViewModel.load()
            homeViewModel.selectHistoryItem(id: id)
        }
        .onReceive(navigationRouter.$command.compactMap { $0 }) { command in
            if let settingsSection = command.settingsSection {
                settingsViewModel.selectedSection = settingsSection
            }
            selectedRoute = command.route
        }
    }

    private func installApplicationPointerMonitor() {
        guard applicationPointerMonitor == nil else {
            return
        }
        applicationPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            homeViewModel.handleApplicationPointerDown()
            return event
        }
    }

    private func removeApplicationPointerMonitor() {
        guard let applicationPointerMonitor else {
            return
        }
        NSEvent.removeMonitor(applicationPointerMonitor)
        self.applicationPointerMonitor = nil
    }

    private var detailView: some View {
        WorkbenchDetailView(
            route: $selectedRoute,
            snapshot: viewModel.snapshot,
            homeViewModel: homeViewModel,
            voiceCorrectionViewModel: voiceCorrectionViewModel,
            styleViewModel: styleViewModel,
            llmProviderViewModel: llmProviderViewModel,
            asrProviderViewModel: asrProviderViewModel,
            settingsViewModel: settingsViewModel,
            fileTranscriptionViewModel: fileTranscriptionViewModel,
            notesViewModel: notesViewModel,
            screenshotRecordViewModel: screenshotRecordViewModel,
            onCheckForUpdates: onCheckForUpdates
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.pageBackground)
    }

    private func sidebarToggle(alignment: Alignment) -> some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 34, height: 34)
                    .appControlSurface(cornerRadius: AppTheme.Radius.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSidebarVisible ? "收起侧栏" : "展开侧栏")
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 48, alignment: alignment)
        .background(AppTheme.ColorToken.sidebarBackground)
    }
}

private struct WorkbenchDetailView: View {
    @Binding var route: NavigationRoute
    let snapshot: WorkbenchSnapshot
    @ObservedObject var homeViewModel: HomeDashboardViewModel
    @ObservedObject var voiceCorrectionViewModel: VoiceCorrectionViewModel
    @ObservedObject var styleViewModel: StyleViewModel
    @ObservedObject var llmProviderViewModel: LLMProviderViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var fileTranscriptionViewModel: FileTranscriptionViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject var screenshotRecordViewModel: ScreenshotRecordViewModel
    let onCheckForUpdates: () -> Void

    var body: some View {
        switch route {
        case .home:
            HomeDashboardView(viewModel: homeViewModel)
        case .vibeCoding:
            VibeCodingStatusView(viewModel: settingsViewModel)
        case .fileTranscription:
            FileTranscriptionView(viewModel: fileTranscriptionViewModel)
        case .notes:
            NotesView(viewModel: notesViewModel)
        case .screenshotRecord:
            ScreenshotRecordView(viewModel: screenshotRecordViewModel)
        case .voiceCorrection:
            VoiceCorrectionView(viewModel: voiceCorrectionViewModel)
        case .styles:
            StyleWorkspaceView(styleViewModel: styleViewModel)
        case .settings:
            SettingsRootView(
                viewModel: settingsViewModel,
                llmProviderViewModel: llmProviderViewModel,
                asrProviderViewModel: asrProviderViewModel,
                onCheckForUpdates: onCheckForUpdates
            )
        case .help:
            HelpView(
                settingsViewModel: settingsViewModel,
                asrProviderViewModel: asrProviderViewModel,
                onOpenPermissions: {
                    settingsViewModel.selectedSection = .dataPrivacy
                    route = .settings
                },
                onCheckForUpdates: onCheckForUpdates
            )
        }
    }
}
