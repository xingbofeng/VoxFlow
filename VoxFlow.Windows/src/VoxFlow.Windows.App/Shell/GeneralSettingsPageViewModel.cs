using VoxFlow.Windows.App.Localization;

#if DEBUG
using VoxFlow.Windows.App.Composition;
#endif

namespace VoxFlow.Windows.App.Shell;

public sealed record GeneralSettingsActions(
    Func<bool> ReadDarkTheme,
    Action<bool> ApplyDarkTheme,
    Func<bool> ReadLaunchAtLogin,
    Action<bool> ApplyLaunchAtLogin,
    Func<string> CreateSanitizedDiagnostics,
    Action<string> CopyText,
    Func<bool>? ReadGrayTrayIcon = null,
    Action<bool>? ApplyGrayTrayIcon = null,
    Func<bool>? ReadCapsLockIndicator = null,
    Action<bool>? ApplyCapsLockIndicator = null,
    Func<bool>? ReadStreamPreview = null,
    Action<bool>? ApplyStreamPreview = null,
    Func<bool>? ReadAutoReleaseModels = null,
    Action<bool>? ApplyAutoReleaseModels = null,
    Func<string>? ReadUiLanguage = null,
    Action<string>? ApplyUiLanguage = null);

public sealed class GeneralSettingsPageViewModel : BindableObject
{
    private readonly GeneralSettingsActions? actions;
    private readonly Func<CancellationToken, Task> resetVoiceAndHotkeys;
    private bool isDarkTheme;
    private bool launchAtLogin;
    private bool grayTrayIcon;
    private bool capsLockIndicator;
    private bool streamPreview = true;
    private bool autoReleaseModels;
    private string uiLanguageId = "system";
    private bool isBusy;
    private string? feedbackMessage;

    public GeneralSettingsPageViewModel(
        string heading,
        string subtitle,
        GeneralSettingsActions? actions = null,
        Func<CancellationToken, Task>? resetVoiceAndHotkeys = null
#if DEBUG
        , Func<
            string,
            DebugTranscriptInjectionMode,
            CancellationToken,
            Task<DebugTranscriptInjectionResult>>? debugTranscriptInjection = null
#endif
        )
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(heading);
        ArgumentException.ThrowIfNullOrWhiteSpace(subtitle);
        Heading = heading;
        Subtitle = subtitle;
        this.actions = actions;
        this.resetVoiceAndHotkeys = resetVoiceAndHotkeys
            ?? (_ => Task.CompletedTask);
        if (actions is not null)
        {
            isDarkTheme = ReadSafely(actions.ReadDarkTheme);
            launchAtLogin = ReadSafely(actions.ReadLaunchAtLogin);
            grayTrayIcon = ReadSafely(actions.ReadGrayTrayIcon);
            capsLockIndicator = ReadSafely(actions.ReadCapsLockIndicator);
            streamPreview = ReadSafely(actions.ReadStreamPreview, defaultValue: true);
            autoReleaseModels = ReadSafely(actions.ReadAutoReleaseModels);
            uiLanguageId = ReadLanguageSafely(actions.ReadUiLanguage);
        }
        UiLanguageChoices =
        [
            new SettingsChoiceViewModel("system", L10n.Localize("SettingsGeneralUiLanguageSystem")),
            new SettingsChoiceViewModel("zh-Hans", L10n.Localize("TrayLanguageChinese")),
            new SettingsChoiceViewModel("zh-Hant", L10n.Localize("SettingsGeneralUiLanguageTraditionalChinese")),
            new SettingsChoiceViewModel("en", L10n.Localize("TrayLanguageEnglish")),
            new SettingsChoiceViewModel("ja", L10n.Localize("TrayLanguageJapanese")),
            new SettingsChoiceViewModel("ko", L10n.Localize("TrayLanguageKorean")),
        ];
#if DEBUG
        DebugTranscript = debugTranscriptInjection is null
            ? null
            : new DebugTranscriptInjectionViewModel(debugTranscriptInjection);
#endif
    }

    public string Heading { get; }

    public string Subtitle { get; }

    public bool CanManageGeneralSettings => actions is not null;

    public IReadOnlyList<SettingsChoiceViewModel> UiLanguageChoices { get; }

    public string UiLanguageId
    {
        get => uiLanguageId;
        set
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return;
            }

            var normalized = value.Trim();
            if (uiLanguageId == normalized)
            {
                return;
            }
            try
            {
                actions?.ApplyUiLanguage?.Invoke(normalized);
                SetField(ref uiLanguageId, normalized);
                FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
            }
            catch
            {
                FeedbackMessage = L10n.Localize("SettingsGeneralActionFailed");
            }
        }
    }

    public bool IsDarkTheme
    {
        get => isDarkTheme;
        set => ApplyToggle(value, actions?.ApplyDarkTheme, ref isDarkTheme);
    }

    public bool LaunchAtLogin
    {
        get => launchAtLogin;
        set => ApplyToggle(value, actions?.ApplyLaunchAtLogin, ref launchAtLogin);
    }

    public bool GrayTrayIcon
    {
        get => grayTrayIcon;
        set => ApplyOptionalToggle(value, actions?.ApplyGrayTrayIcon, ref grayTrayIcon);
    }

    public bool CapsLockIndicator
    {
        get => capsLockIndicator;
        set => ApplyOptionalToggle(value, actions?.ApplyCapsLockIndicator, ref capsLockIndicator);
    }

    public bool StreamPreview
    {
        get => streamPreview;
        set => ApplyOptionalToggle(value, actions?.ApplyStreamPreview, ref streamPreview);
    }

    public bool AutoReleaseModels
    {
        get => autoReleaseModels;
        set => ApplyOptionalToggle(value, actions?.ApplyAutoReleaseModels, ref autoReleaseModels);
    }

    public bool IsBusy
    {
        get => isBusy;
        private set
        {
            if (SetField(ref isBusy, value))
            {
                OnPropertyChanged(nameof(CanExecuteActions));
            }
        }
    }

    public bool CanExecuteActions => CanManageGeneralSettings && !IsBusy;

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

#if DEBUG
    public bool ShowsDebugTools => DebugTranscript is not null;

    public DebugTranscriptInjectionViewModel? DebugTranscript { get; }
#else
    public bool ShowsDebugTools => false;

    public object? DebugTranscript => null;
#endif

    public Task<bool> CopyDiagnosticsAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (actions is null || IsBusy)
        {
            return Task.FromResult(false);
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize("SettingsDiagnosticsCopying");
        try
        {
            var report = actions.CreateSanitizedDiagnostics();
            actions.CopyText(string.IsNullOrWhiteSpace(report)
                ? L10n.Localize("SettingsDiagnosticsEmpty")
                : report);
            FeedbackMessage = L10n.Localize("SettingsDiagnosticsCopied");
            return Task.FromResult(true);
        }
        catch
        {
            FeedbackMessage = L10n.Localize("SettingsGeneralActionFailed");
            return Task.FromResult(false);
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task<bool> ResetAsync(
        bool confirmed,
        CancellationToken cancellationToken)
    {
        if (!confirmed || actions is null || IsBusy)
        {
            return false;
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize("SettingsResetting");
        try
        {
            actions.ApplyDarkTheme(false);
            actions.ApplyLaunchAtLogin(false);
            actions.ApplyGrayTrayIcon?.Invoke(false);
            actions.ApplyCapsLockIndicator?.Invoke(false);
            actions.ApplyStreamPreview?.Invoke(true);
            actions.ApplyAutoReleaseModels?.Invoke(false);
            actions.ApplyUiLanguage?.Invoke("system");
            await resetVoiceAndHotkeys(cancellationToken);
            SetField(ref isDarkTheme, false, nameof(IsDarkTheme));
            SetField(ref launchAtLogin, false, nameof(LaunchAtLogin));
            SetField(ref grayTrayIcon, false, nameof(GrayTrayIcon));
            SetField(ref capsLockIndicator, false, nameof(CapsLockIndicator));
            SetField(ref streamPreview, true, nameof(StreamPreview));
            SetField(ref autoReleaseModels, false, nameof(AutoReleaseModels));
            SetField(ref uiLanguageId, "system", nameof(UiLanguageId));
            FeedbackMessage = L10n.Localize("SettingsResetSucceeded");
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            FeedbackMessage = L10n.Localize("SettingsGeneralActionFailed");
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void ApplyToggle(
        bool value,
        Action<bool>? apply,
        ref bool field,
        [System.Runtime.CompilerServices.CallerMemberName] string? propertyName = null)
    {
        if (field == value)
        {
            return;
        }
        if (apply is null)
        {
            FeedbackMessage = L10n.Localize("SettingsGeneralActionUnavailable");
            return;
        }

        try
        {
            apply(value);
            SetField(ref field, value, propertyName);
            FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
        }
        catch
        {
            FeedbackMessage = L10n.Localize("SettingsGeneralActionFailed");
            OnPropertyChanged(propertyName);
        }
    }

    /// <summary>
    /// Mac-parity rows that may not yet have full Windows backends still update UI state.
    /// </summary>
    private void ApplyOptionalToggle(
        bool value,
        Action<bool>? apply,
        ref bool field,
        [System.Runtime.CompilerServices.CallerMemberName] string? propertyName = null)
    {
        if (field == value)
        {
            return;
        }

        try
        {
            apply?.Invoke(value);
            SetField(ref field, value, propertyName);
            FeedbackMessage = L10n.Localize("SettingsSaveSucceeded");
        }
        catch
        {
            FeedbackMessage = L10n.Localize("SettingsGeneralActionFailed");
            OnPropertyChanged(propertyName);
        }
    }

    private static bool ReadSafely(Func<bool>? read, bool defaultValue = false)
    {
        if (read is null)
        {
            return defaultValue;
        }

        try
        {
            return read();
        }
        catch
        {
            return defaultValue;
        }
    }

    private static string ReadLanguageSafely(Func<string>? read)
    {
        try
        {
            return read?.Invoke() switch
            {
                "zh-Hans" => "zh-Hans",
                "zh-Hant" => "zh-Hant",
                "en" => "en",
                "ja" => "ja",
                "ko" => "ko",
                _ => "system",
            };
        }
        catch
        {
            return "system";
        }
    }
}
