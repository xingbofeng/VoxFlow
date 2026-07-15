using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.Settings;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Platform.Input;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class InteractiveHotkeySettingsPresentationTests
{
    [Fact]
    public async Task Defaults_project_mac_parity_alt_shift_bindings_for_all_workflow_rows()
    {
        var settings = new MemoryInteractiveHotkeySettingsStore();
        var viewModel = new InteractiveHotkeySettingsViewModel(settings);

        await viewModel.InitializeAsync(CancellationToken.None);

        Assert.Equal(InteractiveHotkeyAction.Screenshot, viewModel.Screenshot.Action);
        Assert.Equal(
            InteractiveHotkeyAction.ClipboardImageOcr,
            viewModel.ClipboardImageOcr.Action);
        Assert.Equal(InteractiveHotkeyAction.AgentCompose, viewModel.Agent.Action);
        Assert.Equal(
            [
                InteractiveHotkeyAction.SelectionTranslation,
                InteractiveHotkeyAction.SelectionSummary,
            ],
            viewModel.TranslationRows.Select(row => row.Action));
        Assert.True(viewModel.Screenshot.IsBound);
        Assert.Equal("Alt+Shift+A", viewModel.Screenshot.BindingDisplay);
        Assert.True(viewModel.ClipboardImageOcr.IsBound);
        Assert.Equal("Alt+Shift+V", viewModel.ClipboardImageOcr.BindingDisplay);
        Assert.True(viewModel.TranslationRows[0].IsBound);
        Assert.Equal("Alt+Shift+F", viewModel.TranslationRows[0].BindingDisplay);
        Assert.True(viewModel.TranslationRows[1].IsBound);
        Assert.Equal("Alt+Shift+K", viewModel.TranslationRows[1].BindingDisplay);
        Assert.True(viewModel.Agent.IsBound);
        Assert.Equal("Alt+Shift+L", viewModel.Agent.BindingDisplay);
        Assert.True(viewModel.AskAi.IsBound);
        Assert.Equal("Alt+Shift+P", viewModel.AskAi.BindingDisplay);
    }

    [Fact]
    public async Task Screenshot_rebind_clear_restore_and_duplicate_conflict_are_persisted()
    {
        var store = new MemoryInteractiveHotkeySettingsStore();
        var viewModel = new InteractiveHotkeySettingsViewModel(store);
        await viewModel.InitializeAsync(CancellationToken.None);
        var screenshot = viewModel.Screenshot;

        var rebound = await screenshot.ApplyCapturedBindingAsync(
            new HotkeyBinding(
                VirtualKey: 0x53,
                ScanCode: 0x1F,
                Modifiers: HotkeyModifiers.Alt | HotkeyModifiers.Shift,
                IsExtended: false),
            CancellationToken.None);
        await screenshot.ClearAsync(CancellationToken.None);
        await screenshot.RestoreDefaultAsync(CancellationToken.None);
        // Free F so a custom T binding can be assigned without colliding with defaults.
        await viewModel.TranslationRows[0].ClearAsync(CancellationToken.None);
        var translationBinding = new HotkeyBinding(
            VirtualKey: 0x54,
            ScanCode: 0x14,
            Modifiers: HotkeyModifiers.Alt | HotkeyModifiers.Shift,
            IsExtended: false);
        Assert.True(await viewModel.TranslationRows[0].ApplyCapturedBindingAsync(
            translationBinding,
            CancellationToken.None));
        var duplicate = await screenshot.ApplyCapturedBindingAsync(
            translationBinding,
            CancellationToken.None);

        Assert.True(rebound);
        Assert.False(duplicate);
        Assert.Equal(HotkeyConflictKind.AlreadyAssigned, screenshot.Conflict);
        Assert.True(screenshot.IsBound);
        Assert.Equal(InteractiveHotkeySettingsDocument.ScreenshotDefault, store.Current.Screenshot);
    }

    [Fact]
    public async Task Saved_binding_is_published_to_the_live_input_route_without_restart()
    {
        var store = new MemoryInteractiveHotkeySettingsStore();
        InteractiveHotkeyBindingSet? published = null;
        var viewModel = new InteractiveHotkeySettingsViewModel(
            store,
            bindings => published = bindings);
        await viewModel.InitializeAsync(CancellationToken.None);
        var replacement = new HotkeyBinding(
            VirtualKey: 0x54,
            ScanCode: 0x14,
            Modifiers: HotkeyModifiers.Alt | HotkeyModifiers.Shift,
            IsExtended: false);

        Assert.True(await viewModel.TranslationRows[0].ApplyCapturedBindingAsync(
            replacement,
            CancellationToken.None));

        Assert.Equal(replacement, published?.SelectionTranslation);
    }

    [Fact]
    public async Task Recording_cancel_clear_restore_and_conflict_preserve_one_valid_projection()
    {
        var store = new MemoryInteractiveHotkeySettingsStore();
        var viewModel = new InteractiveHotkeySettingsViewModel(store);
        await viewModel.InitializeAsync(CancellationToken.None);
        var translation = viewModel.TranslationRows[0];
        var summary = viewModel.TranslationRows[1];

        translation.BeginRecording();
        Assert.True(translation.IsRecording);
        translation.CancelRecording();
        Assert.False(translation.IsRecording);

        await translation.ClearAsync(CancellationToken.None);
        Assert.False(translation.IsBound);
        Assert.Equal(InteractiveHotkeySettingsDocument.CurrentSchemaVersion, store.Current.SchemaVersion);

        await translation.RestoreDefaultAsync(CancellationToken.None);
        Assert.True(translation.IsBound);
        Assert.Equal("Alt+Shift+F", translation.BindingDisplay);
        var translationBinding = translation.Binding
            ?? throw new InvalidOperationException("Expected restored default.");
        await summary.ClearAsync(CancellationToken.None);
        var beforeConflict = summary.BindingDisplay;
        var duplicate = await summary.ApplyCapturedBindingAsync(
            translationBinding,
            CancellationToken.None);

        Assert.False(duplicate);
        Assert.True(summary.HasConflict);
        Assert.Equal(HotkeyConflictKind.AlreadyAssigned, summary.Conflict);
        Assert.Equal(beforeConflict, summary.BindingDisplay);
        Assert.Null(InteractiveHotkeyBindingSet
            .FromSettings(store.Current)
            .Get(InteractiveHotkeyAction.SelectionSummary));
    }

    [Fact]
    public async Task Hotkey_buttons_expose_only_actions_valid_for_the_current_row_state()
    {
        var viewModel = new InteractiveHotkeySettingsViewModel(
            new MemoryInteractiveHotkeySettingsStore());
        await viewModel.InitializeAsync(CancellationToken.None);
        var row = viewModel.Screenshot;

        Assert.True(row.CanRecord);
        Assert.False(row.CanCancel);
        Assert.Equal(row.IsBound, row.CanClear);

        row.BeginRecording();

        Assert.False(row.CanRecord);
        Assert.True(row.CanCancel);
        Assert.False(row.CanClear);
        Assert.False(row.CanRestoreDefault);

        row.CancelRecording();

        Assert.True(row.CanRecord);
        Assert.False(row.CanCancel);
    }

    [Fact]
    public async Task Hotkey_persistence_failure_is_safe_visible_and_does_not_escape_the_handler()
    {
        var viewModel = new InteractiveHotkeySettingsViewModel(
            new FailingInteractiveHotkeySettingsStore());
        await viewModel.InitializeAsync(CancellationToken.None);

        var saved = await viewModel.Screenshot.ApplyCapturedBindingAsync(
            new HotkeyBinding(
                VirtualKey: 0x7B,
                ScanCode: 0x58,
                Modifiers: HotkeyModifiers.Alt | HotkeyModifiers.Shift,
                IsExtended: false),
            CancellationToken.None);

        Assert.False(saved);
        var feedback = Assert.IsType<string>(viewModel.Screenshot.ActionFeedback);
        Assert.Equal(
            VoxFlow.Windows.App.Localization.L10n.Localize("SettingsOperationFailed"),
            feedback);
        Assert.DoesNotContain(
            "sensitive fixture failure",
            feedback,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Right_alt_capture_shows_AltGr_risk_and_is_not_saved()
    {
        var store = new MemoryInteractiveHotkeySettingsStore();
        var viewModel = new InteractiveHotkeySettingsViewModel(store);
        await viewModel.InitializeAsync(CancellationToken.None);
        var agent = viewModel.Agent;

        var before = agent.Binding;
        var saved = await agent.ApplyCapturedBindingAsync(
            new HotkeyBinding(
                RightControlKeyClassifier.VirtualKeyRightMenu,
                0x38,
                HotkeyModifiers.Control | HotkeyModifiers.Alt,
                IsExtended: true),
            CancellationToken.None);

        Assert.False(saved);
        Assert.True(agent.HasConflict);
        Assert.True(agent.ShowsAltGrRisk);
        // Default Alt+Shift+L remains; Right Alt must not replace it.
        Assert.Equal(before, agent.Binding);
        Assert.NotEqual(
            RightControlKeyClassifier.VirtualKeyRightMenu,
            agent.Binding?.VirtualKey);
    }

    [Fact]
    public async Task Enabled_settings_add_translation_and_agent_rows_while_disabled_shape_stays_unchanged()
    {
        var store = new MemoryInteractiveHotkeySettingsStore();
        var enabled = new SettingsPageViewModel(
            "Settings",
            "Configure VoxFlow",
            new VoxFlowStateStore(),
            new MemoryTextSettingsStore(),
            openAiSettingsService: null,
            cloudAsrSettings: null,
            llmProviderManagement: null,
            interactiveHotkeySettingsStore: store,
            interactiveFeatureFlags: new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true));

        await enabled.InitializeAsync(CancellationToken.None);

        Assert.Equal(
            ["general", "models", "voice", "text", "screenshot", "selection-assistant"],
            enabled.NavigationItems.Select(item => item.Id));
        Assert.True(enabled.TryNavigate("voice"));
        Assert.NotNull(Assert.IsType<VoiceSettingsPageViewModel>(enabled.CurrentPage).AgentHotkey);
        Assert.True(enabled.TryNavigate("translation"));
        Assert.Equal(
            4,
            Assert.IsType<TranslationSettingsPageViewModel>(enabled.CurrentPage)
                .HotkeyRows.Count);
    }

    [Fact]
    public async Task Screenshot_page_exposes_clipboard_and_capture_rows_when_interactive_features_are_disabled()
    {
        var store = new MemoryInteractiveHotkeySettingsStore();
        var settings = new SettingsPageViewModel(
            "Settings",
            "Configure VoxFlow",
            new VoxFlowStateStore(),
            new MemoryTextSettingsStore(),
            openAiSettingsService: null,
            cloudAsrSettings: null,
            llmProviderManagement: null,
            interactiveHotkeySettingsStore: store,
            interactiveFeatureFlags: WindowsInteractiveFeatureFlags.Disabled);

        await settings.InitializeAsync(CancellationToken.None);

        Assert.True(settings.TryNavigate("voice"));
        var voice = Assert.IsType<VoiceSettingsPageViewModel>(settings.CurrentPage);
        Assert.Null(voice.AgentHotkey);
        Assert.False(settings.TryNavigate("translation"));
        Assert.True(settings.TryNavigate("screenshot"));
        var screenshot = Assert.IsType<ScreenshotSettingsPageViewModel>(settings.CurrentPage);
        Assert.Equal(InteractiveHotkeyAction.Screenshot, screenshot.ScreenshotHotkey.Action);
        Assert.Equal(
            InteractiveHotkeyAction.ClipboardImageOcr,
            screenshot.ClipboardImageOcrHotkey.Action);
        Assert.True(screenshot.ClipboardOcrEnabled);
    }

    [Fact]
    public async Task Screenshot_settings_view_renders_clipboard_then_capture_hotkey_rows()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var hotkeys = new InteractiveHotkeySettingsViewModel(
                new MemoryInteractiveHotkeySettingsStore());
            await hotkeys.InitializeAsync(CancellationToken.None);
            var page = new ScreenshotSettingsPageViewModel(
                hotkeys,
                new InMemoryScreenshotAutomationSettingsStore());
            await page.LoadAsync(CancellationToken.None);
            var view = new ScreenshotSettingsView
            {
                DataContext = page,
            };
            var host = new Window
            {
                Content = view,
                ShowActivated = false,
                ShowInTaskbar = false,
                WindowStyle = WindowStyle.None,
                Opacity = 0,
            };
            try
            {
                host.Show();
                view.UpdateLayout();
                var rows = FindVisualChildren<InteractiveHotkeyRowView>(view).ToArray();
                Assert.Equal(2, rows.Length);
                Assert.Same(hotkeys.ClipboardImageOcr, rows[0].DataContext);
                Assert.Same(hotkeys.Screenshot, rows[1].DataContext);
                Assert.Equal(
                    hotkeys.ClipboardImageOcr.Title,
                    AutomationProperties.GetName(rows[0]));
                Assert.Equal(
                    hotkeys.ClipboardImageOcr.Description,
                    AutomationProperties.GetHelpText(rows[0]));
            }
            finally
            {
                host.Close();
            }
        });
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject root)
        where T : DependencyObject
    {
        if (root is null)
        {
            yield break;
        }

        var count = System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < count; index++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(root, index);
            if (child is T match)
            {
                yield return match;
            }

            foreach (var nested in FindVisualChildren<T>(child))
            {
                yield return nested;
            }
        }
    }

    [Fact]
    public void Hotkey_settings_copy_is_complete_in_all_five_languages()
    {
        string[] keys =
        [
            "SettingsNavigationTranslation",
            "SettingsTranslationHeading",
            "SettingsTranslationSubtitle",
            "SettingsHotkeySelectionTranslationTitle",
            "SettingsHotkeySelectionTranslationDescription",
            "SettingsHotkeySelectionSummaryTitle",
            "SettingsHotkeySelectionSummaryDescription",
            "SettingsHotkeyAgentComposeTitle",
            "SettingsHotkeyAgentComposeDescription",
            "SettingsHotkeyScreenshotTitle",
            "SettingsHotkeyScreenshotDescription",
            "SettingsHotkeyClipboardImageOcrTitle",
            "SettingsHotkeyClipboardImageOcrDescription",
            "SettingsScreenshotHeading",
            "SettingsScreenshotSubtitle",
            "SettingsScreenshotHotkeyHeading",
            "SettingsScreenshotHotkeyDescription",
            "SettingsScreenshotClipboardHeading",
            "SettingsScreenshotClipboardDescription",
            "SettingsScreenshotClipboardToggle",
            "SettingsScreenshotClipboardToggleDescription",
            "SettingsGeneralBasicsHeading",
            "SettingsGeneralBasicsDescription",
            "SettingsGeneralDarkThemeDescription",
            "SettingsGeneralLaunchAtLoginDescription",
            "SettingsGeneralPermissionsDescription",
            "SettingsGeneralDataDescription",
            "ClipboardImageOcrNoImage",
            "ClipboardImageOcrNoText",
            "ClipboardImageOcrDisabled",
            "SettingsHotkeyAgentSectionTitle",
            "SettingsHotkeyAgentSectionDescription",
            "SettingsHotkeyRecord",
            "SettingsHotkeyModify",
            "SettingsHotkeyCancel",
            "SettingsHotkeyClear",
            "SettingsHotkeyRestoreDefault",
            "SettingsHotkeyUnbound",
            "SettingsHotkeyRecordingStatus",
            "SettingsHotkeySelectionAskAiTitle",
            "SettingsHotkeySelectionAskAiDescription",
            "SettingsGeneralUiLanguage",
            "SettingsGeneralGrayTrayIcon",
            "SettingsGeneralCapsLockIndicator",
            "SettingsGeneralStreamPreview",
            "SettingsGeneralAutoReleaseModels",
            "SettingsTextDeterministicHeading",
            "SettingsTextMasterDescription",
            "SettingsSelectionSectionHeading",
            "SettingsVoiceDictationTitle",
            "hotkey.conflict.alreadyAssigned",
            "hotkey.conflict.altGrUnsafe",
            "hotkey.conflict.systemEditing",
        ];
        CultureInfo[] cultures =
        [
            new("en"), new("zh-Hans"), new("zh-Hant"), new("ja"), new("ko"),
        ];

        foreach (var culture in cultures)
        {
            foreach (var key in keys)
            {
                var value = VoxFlow.Windows.App.Localization.L10n.Localize(key, culture);
                Assert.False(string.IsNullOrWhiteSpace(value));
                Assert.NotEqual(key, value);
            }
        }
    }

    private sealed class MemoryInteractiveHotkeySettingsStore
        : IInteractiveHotkeySettingsStore
    {
        public InteractiveHotkeySettingsDocument Current { get; private set; } =
            InteractiveHotkeySettingsDocument.Default;

        public ValueTask<InteractiveHotkeySettingsDocument> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(Current);

        public ValueTask SaveAsync(
            InteractiveHotkeySettingsDocument settings,
            CancellationToken cancellationToken)
        {
            Current = settings;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FailingInteractiveHotkeySettingsStore
        : IInteractiveHotkeySettingsStore
    {
        public ValueTask<InteractiveHotkeySettingsDocument> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(InteractiveHotkeySettingsDocument.Default);

        public ValueTask SaveAsync(
            InteractiveHotkeySettingsDocument settings,
            CancellationToken cancellationToken) =>
            ValueTask.FromException(
                new InvalidOperationException("sensitive fixture failure"));
    }

    private sealed class MemoryTextSettingsStore : ITextProcessingSettingsStore
    {
        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(DeterministicTextProcessingSettings.Default);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }

    private sealed class InMemoryScreenshotAutomationSettingsStore
        : IScreenshotAutomationSettingsStore
    {
        private ScreenshotAutomationSettings settings = ScreenshotAutomationSettings.Default;

        public ValueTask<ScreenshotAutomationSettings> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(settings);

        public ValueTask SaveAsync(
            ScreenshotAutomationSettings value,
            CancellationToken cancellationToken)
        {
            settings = value;
            return ValueTask.CompletedTask;
        }
    }
}
