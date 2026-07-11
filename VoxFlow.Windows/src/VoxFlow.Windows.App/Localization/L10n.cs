using System.Globalization;
using System.Resources;

namespace VoxFlow.Windows.App.Localization;

public static class L10n
{
    private static readonly ResourceManager Resources = new(
        "VoxFlow.Windows.App.Localization.Resources.Strings",
        typeof(L10n).Assembly);

    public static string WindowTitle => Localize("WindowTitle");

    public static string BrandName => Localize("BrandName");

    public static string SidebarToggleAccessibleName =>
        Localize("SidebarToggleAccessibleName");

    public static string HomeStatsTotal => Localize("HomeStatsTotal");

    public static string HomeStatsToday => Localize("HomeStatsToday");

    public static string HomeStatsCharacters => Localize("HomeStatsCharacters");

    public static string HomeStatsDuration => Localize("HomeStatsDuration");

    public static string HomeActivityTitle => Localize("HomeActivityTitle");

    public static string HistoryTitle => Localize("HistoryTitle");

    public static string HistorySearchLabel => Localize("HistorySearchLabel");

    public static string HistorySourceLabel => Localize("HistorySourceLabel");

    public static string HistoryEmpty => Localize("HistoryEmpty");

    public static string HistorySelect => Localize("HistorySelect");

    public static string HistoryCopy => Localize("HistoryCopy");

    public static string HistoryDetails => Localize("HistoryDetails");

    public static string HistoryDelete => Localize("HistoryDelete");

    public static string HistoryDeleteSelected => Localize("HistoryDeleteSelected");

    public static string HistoryClearAll => Localize("HistoryClearAll");

    public static string HistoryPreviousPage => Localize("HistoryPreviousPage");

    public static string HistoryNextPage => Localize("HistoryNextPage");

    public static string HistoryDetailTitle => Localize("HistoryDetailTitle");

    public static string HistoryDetailClose => Localize("HistoryDetailClose");

    public static string HistoryDetailRawText => Localize("HistoryDetailRawText");

    public static string HistoryDetailFinalText => Localize("HistoryDetailFinalText");

    public static string HistoryDetailMetadata => Localize("HistoryDetailMetadata");

    public static string HistoryDetailLanguage => Localize("HistoryDetailLanguage");

    public static string HistoryDetailDuration => Localize("HistoryDetailDuration");

    public static string HistoryDetailLlmDuration => Localize("HistoryDetailLlmDuration");

    public static string HistoryDetailFrames => Localize("HistoryDetailFrames");

    public static string HistoryDetailSave => Localize("HistoryDetailSave");

    public static string HistoryDetailReprocess => Localize("HistoryDetailReprocess");

    public static string HistoryDetailDiagnostic => Localize("HistoryDetailDiagnostic");

    public static string HistoryDetailCopyDiagnostic =>
        Localize("HistoryDetailCopyDiagnostic");

    public static string SettingsGeneralAppearance => Localize("SettingsGeneralAppearance");

    public static string SettingsGeneralDarkTheme => Localize("SettingsGeneralDarkTheme");

    public static string SettingsGeneralLaunchAtLogin => Localize("SettingsGeneralLaunchAtLogin");

    public static string SettingsGeneralPermissions => Localize("SettingsGeneralPermissions");

    public static string SettingsGeneralOpenMicrophonePrivacy =>
        Localize("SettingsGeneralOpenMicrophonePrivacy");

    public static string SettingsGeneralData => Localize("SettingsGeneralData");

    public static string SettingsGeneralCopyDiagnostics =>
        Localize("SettingsGeneralCopyDiagnostics");

    public static string SettingsGeneralReset => Localize("SettingsGeneralReset");

    public static string SettingsVoiceDevice => Localize("SettingsVoiceDevice");

    public static string SettingsVoiceLanguage => Localize("SettingsVoiceLanguage");

    public static string SettingsVoiceInteraction => Localize("SettingsVoiceInteraction");

    public static string SettingsVoiceMiddleMouse => Localize("SettingsVoiceMiddleMouse");

    public static string SettingsVoiceMutePlayback => Localize("SettingsVoiceMutePlayback");

    public static string SettingsVoiceFeedbackSounds => Localize("SettingsVoiceFeedbackSounds");

    public static string SettingsVoiceEnhancement => Localize("SettingsVoiceEnhancement");

    public static string SettingsVoiceQuickPaste => Localize("SettingsVoiceQuickPaste");

    public static string SettingsVoiceQuickPasteDescription =>
        Localize("SettingsVoiceQuickPasteDescription");

    public static string SettingsVoiceSimulatedTyping =>
        Localize("SettingsVoiceSimulatedTyping");

    public static string SettingsVoiceSimulatedTypingDescription =>
        Localize("SettingsVoiceSimulatedTypingDescription");

    public static string SettingsVoiceKeepMicrophoneActive =>
        Localize("SettingsVoiceKeepMicrophoneActive");

    public static string SettingsTextMaster => Localize("SettingsTextMaster");

    public static string SettingsTextSmartNumbers => Localize("SettingsTextSmartNumbers");

    public static string SettingsTextPunctuation => Localize("SettingsTextPunctuation");

    public static string SettingsTextLongSentences => Localize("SettingsTextLongSentences");

    public static string SettingsTextFillerWords => Localize("SettingsTextFillerWords");

    public static string SettingsTextCjkSpacing => Localize("SettingsTextCjkSpacing");

    public static string SettingsTextCapitalization => Localize("SettingsTextCapitalization");

    public static string SettingsTextWordBreakThreshold =>
        Localize("SettingsTextWordBreakThreshold");

    public static string SettingsTextCjkBreakThreshold =>
        Localize("SettingsTextCjkBreakThreshold");

    public static string SettingsTextCjkPunctuationThreshold =>
        Localize("SettingsTextCjkPunctuationThreshold");

    public static string SettingsTextWordPunctuationThreshold =>
        Localize("SettingsTextWordPunctuationThreshold");

    public static string SettingsActionApply => Localize("SettingsActionApply");

    public static string SettingsOpenAiBaseUrl => Localize("SettingsOpenAiBaseUrl");

    public static string SettingsOpenAiModel => Localize("SettingsOpenAiModel");

    public static string SettingsOpenAiApiKey => Localize("SettingsOpenAiApiKey");

    public static string SettingsOpenAiEnabled => Localize("SettingsOpenAiEnabled");

    public static string SettingsActionSave => Localize("SettingsActionSave");

    public static string SettingsActionTest => Localize("SettingsActionTest");

    public static string SettingsActionDelete => Localize("SettingsActionDelete");

    public static string SettingsCredentialAppId => Localize("SettingsCredentialAppId");

    public static string SettingsCredentialSecretId => Localize("SettingsCredentialSecretId");

    public static string SettingsCredentialSecretKey => Localize("SettingsCredentialSecretKey");

    public static string SettingsCredentialApiKey => Localize("SettingsCredentialApiKey");

    public static string SettingsCredentialAccessToken =>
        Localize("SettingsCredentialAccessToken");

    public static string SettingsCloudAudioNotice => Localize("SettingsCloudAudioNotice");

    public static string Localize(string key, CultureInfo? culture = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        return Resources.GetString(key, culture ?? CultureInfo.CurrentUICulture)
            ?? Resources.GetString(key, CultureInfo.InvariantCulture)
            ?? throw new MissingManifestResourceException(
                $"The localized resource '{key}' is missing.");
    }
}
