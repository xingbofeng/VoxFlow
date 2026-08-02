using System.Windows;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class MainShellLayoutTests
{
    [Fact]
    public async Task Main_window_enforces_the_v1_minimum_size_contract()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new MainWindow();

            Assert.Equal(1120D, window.MinWidth);
            Assert.Equal(720D, window.MinHeight);

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public void Sidebar_switches_between_220_expanded_and_56_collapsed_pixels()
    {
        var viewModel = new MainShellViewModel();

        Assert.False(viewModel.IsSidebarCollapsed);
        Assert.Equal(new GridLength(220), viewModel.SidebarWidth);

        viewModel.ToggleSidebar();

        Assert.True(viewModel.IsSidebarCollapsed);
        Assert.Equal(new GridLength(56), viewModel.SidebarWidth);
    }

    [Fact]
    public void Navigation_exposes_the_full_macOS_feature_hierarchy()
    {
        var viewModel = new MainShellViewModel();

        Assert.Equal(
            [
                ShellRoute.Home,
                ShellRoute.Media,
                ShellRoute.AgentWorkspace,
                ShellRoute.Glossary,
                ShellRoute.WritingStyles,
                ShellRoute.FileTranscription,
                ShellRoute.Notes,
                ShellRoute.Settings,
                ShellRoute.Help,
            ],
            viewModel.NavigationItems.Select(item => item.Route));
        Assert.Equal(ShellRoute.Home, viewModel.CurrentRoute);

        Assert.True(viewModel.TryNavigate("settings"));
        Assert.Equal(ShellRoute.Settings, viewModel.CurrentRoute);
        Assert.True(viewModel.TryNavigate("file-transcription"));
        Assert.Equal(ShellRoute.FileTranscription, viewModel.CurrentRoute);
        Assert.True(viewModel.TryNavigate("media"));
        Assert.Equal(ShellRoute.Media, viewModel.CurrentRoute);
        Assert.True(viewModel.TryNavigate("screenshot"));
        Assert.Equal(ShellRoute.Media, viewModel.CurrentRoute);
        Assert.True(viewModel.TryNavigate("glossary"));
        Assert.IsType<GlossaryPageViewModel>(viewModel.CurrentPage);
        Assert.True(viewModel.TryNavigate("styles"));
        Assert.IsType<WritingStylesPageViewModel>(viewModel.CurrentPage);
        Assert.True(viewModel.TryNavigate("home"));
        Assert.Equal(ShellRoute.Home, viewModel.CurrentRoute);
    }

    [Fact]
    public void Shell_route_contract_contains_the_screenshot_media_destination()
    {
        Assert.Equal(
            [
                nameof(ShellRoute.Home),
                nameof(ShellRoute.Media),
                nameof(ShellRoute.AgentWorkspace),
                nameof(ShellRoute.Glossary),
                nameof(ShellRoute.WritingStyles),
                nameof(ShellRoute.FileTranscription),
                nameof(ShellRoute.Notes),
                nameof(ShellRoute.Settings),
                nameof(ShellRoute.Help),
            ],
            Enum.GetNames<ShellRoute>());
    }

    [Fact]
    public void Shell_uses_the_injected_settings_page_that_shares_the_process_state_store()
    {
        var stateStore = new VoxFlowStateStore();
        var settings = new SettingsPageViewModel(
            "Settings",
            "Configure VoxFlow",
            stateStore,
            new FakeTextSettingsStore());
        var shell = new MainShellViewModel(
            homeDashboard: null,
            settingsPage: settings,
            fileTranscriptionPage: null);

        Assert.True(shell.TryNavigate("settings"));
        Assert.Same(settings, shell.CurrentPage);
        Assert.True(settings.TryNavigate("voice"));
        var voice = Assert.IsType<VoiceSettingsPageViewModel>(settings.CurrentPage);
        voice.MiddleMouseEnabled = true;
        Assert.Equal("true", stateStore.Current.State.Settings["voice.middleMouseEnabled"]);
    }

    private sealed class FakeTextSettingsStore : ITextProcessingSettingsStore
    {
        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(DeterministicTextProcessingSettings.Default);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }
}
