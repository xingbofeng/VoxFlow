using VoxFlow.Windows.App.Shell;

#if DEBUG
using VoxFlow.Windows.App.Composition;
#endif

namespace VoxFlow.Windows.App.Tests;

public sealed class GeneralSettingsPageViewModelTests
{
    [Fact]
    public async Task Every_general_control_invokes_a_real_action_and_reports_feedback()
    {
        var dark = false;
        var launch = false;
        var resetCalls = 0;
        string? clipboard = null;
        var viewModel = new GeneralSettingsPageViewModel(
            "General",
            "General settings",
            new GeneralSettingsActions(
                () => dark,
                value => dark = value,
                () => launch,
                value => launch = value,
                () => "sanitized diagnostics",
                value => clipboard = value),
            _ =>
            {
                resetCalls++;
                return Task.CompletedTask;
            });

        viewModel.IsDarkTheme = true;
        viewModel.LaunchAtLogin = true;
        var copied = await viewModel.CopyDiagnosticsAsync(CancellationToken.None);
        var reset = await viewModel.ResetAsync(true, CancellationToken.None);

        Assert.True(copied);
        Assert.True(reset);
        Assert.False(dark);
        Assert.False(launch);
        Assert.Equal("sanitized diagnostics", clipboard);
        Assert.Equal(1, resetCalls);
        Assert.False(viewModel.IsBusy);
        Assert.True(viewModel.CanExecuteActions);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.FeedbackMessage));
    }

    [Fact]
    public async Task Failed_platform_action_is_visible_and_does_not_change_the_toggle()
    {
        var viewModel = new GeneralSettingsPageViewModel(
            "General",
            "General settings",
            new GeneralSettingsActions(
                () => false,
                _ => throw new InvalidOperationException("private platform detail"),
                () => false,
                _ => { },
                () => string.Empty,
                _ => { }));

        viewModel.IsDarkTheme = true;

        Assert.False(viewModel.IsDarkTheme);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.FeedbackMessage));
        Assert.DoesNotContain("private platform detail", viewModel.FeedbackMessage);
        Assert.False(await viewModel.ResetAsync(false, CancellationToken.None));
    }

    [Fact]
    public void Mac_parity_general_controls_apply_and_expose_all_supported_ui_languages()
    {
        var gray = false;
        var capsLock = false;
        var stream = true;
        var autoRelease = false;
        var language = "system";
        var viewModel = new GeneralSettingsPageViewModel(
            "General",
            "General settings",
            new GeneralSettingsActions(
                () => false,
                _ => { },
                () => false,
                _ => { },
                () => string.Empty,
                _ => { },
                () => gray,
                value => gray = value,
                () => capsLock,
                value => capsLock = value,
                () => stream,
                value => stream = value,
                () => autoRelease,
                value => autoRelease = value,
                () => language,
                value => language = value));

        viewModel.GrayTrayIcon = true;
        viewModel.CapsLockIndicator = true;
        viewModel.StreamPreview = false;
        viewModel.AutoReleaseModels = true;
        viewModel.UiLanguageId = "zh-Hant";

        Assert.True(gray);
        Assert.True(capsLock);
        Assert.False(stream);
        Assert.True(autoRelease);
        Assert.Equal("zh-Hant", language);
        Assert.Equal(
            ["system", "zh-Hans", "zh-Hant", "en", "ja", "ko"],
            viewModel.UiLanguageChoices.Select(choice => choice.Id));
    }

#if DEBUG
    [Fact]
    public async Task Debug_card_runs_only_the_selected_injected_downstream_mode()
    {
        DebugTranscriptInjectionMode? observedMode = null;
        var viewModel = new GeneralSettingsPageViewModel(
            "General",
            "General settings",
            debugTranscriptInjection: (text, mode, _) =>
            {
                Assert.False(string.IsNullOrWhiteSpace(text));
                observedMode = mode;
                return Task.FromResult(new DebugTranscriptInjectionResult(
                    DebugTranscriptInjectionStatus.Completed));
            });

        Assert.True(viewModel.ShowsDebugTools);
        Assert.NotNull(viewModel.DebugTranscript);
        viewModel.DebugTranscript!.SelectedModeId = "dictation";

        Assert.True(await viewModel.DebugTranscript.RunAsync(CancellationToken.None));
        Assert.Equal(DebugTranscriptInjectionMode.Dictation, observedMode);
        Assert.False(viewModel.DebugTranscript.IsBusy);
    }
#endif
}
