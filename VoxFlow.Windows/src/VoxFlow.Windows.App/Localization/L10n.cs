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

    public static string HomeStatsClipboard => Localize("HomeStatsClipboard");

    public static string HomeStatsReusable => Localize("HomeStatsReusable");

    public static string HomeActivityTitle => Localize("HomeActivityTitle");

    public static string HomeActivitySubtitle => Localize("HomeActivitySubtitle");

    public static string HomeActivityLess => Localize("HomeActivityLess");

    public static string HomeActivityMore => Localize("HomeActivityMore");

    public static string HistorySelectAll => Localize("HistorySelectAll");

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

    public static string HistoryNoPreview => Localize("HistoryNoPreview");

    public static string HistoryContentTypeVoice => Localize("HistoryContentTypeVoice");

    public static string HistoryContentTypeImage => Localize("HistoryContentTypeImage");

    public static string HistoryContentTypeFile => Localize("HistoryContentTypeFile");

    public static string HistoryContentTypeWorkflow => Localize("HistoryContentTypeWorkflow");

    public static string HistoryContentTypeText => Localize("HistoryContentTypeText");

    public static string HistoryDetailClose => Localize("HistoryDetailClose");

    public static string HistoryDetailRawText => Localize("HistoryDetailRawText");

    public static string HistoryDetailFinalText => Localize("HistoryDetailFinalText");

    public static string HistoryDetailMetadata => Localize("HistoryDetailMetadata");

    public static string HistoryDetailLanguage => Localize("HistoryDetailLanguage");

    public static string HistoryDetailAsr => Localize("HistoryDetailAsr");

    public static string HistoryDetailQwen => Localize("HistoryDetailQwen");

    public static string HistoryDetailLlm => Localize("HistoryDetailLlm");

    public static string HistoryDetailDuration => Localize("HistoryDetailDuration");

    public static string HistoryDetailLlmDuration => Localize("HistoryDetailLlmDuration");

    public static string LlmProviderBadge => Localize("LlmProviderBadge");

    public static string HistoryDetailFrames => Localize("HistoryDetailFrames");

    public static string HistoryDetailSave => Localize("HistoryDetailSave");

    public static string HistoryDetailReprocess => Localize("HistoryDetailReprocess");

    public static string HistoryDetailDiagnostic => Localize("HistoryDetailDiagnostic");

    public static string HistoryDetailCopyDiagnostic =>
        Localize("HistoryDetailCopyDiagnostic");

    public static string HistoryDetailWorkflowMetadata =>
        Localize("HistoryDetailWorkflowMetadata");

    public static string HistoryDetailStatus => Localize("HistoryDetailStatus");

    public static string SelectionResultSource => Localize("SelectionResultSource");
    public static string SelectionResultResult => Localize("SelectionResultResult");
    public static string SelectionResultCopy => Localize("SelectionResultCopy");
    public static string SelectionResultSpeak => Localize("SelectionResultSpeak");
    public static string SelectionResultStopSpeaking => Localize("SelectionResultStopSpeaking");
    public static string SelectionResultReplace => Localize("SelectionResultReplace");
    public static string SelectionResultInsertBelow => Localize("SelectionResultInsertBelow");
    public static string SelectionResultProcessing => Localize("SelectionResultProcessing");
    public static string SelectionResultTranslation => Localize("SelectionResultTranslation");
    public static string SelectionResultSummary => Localize("SelectionResultSummary");
    public static string ScreenshotStart => Localize("ScreenshotStart");
    public static string ScreenshotMediaStatsTotal => Localize("ScreenshotMediaStatsTotal");
    public static string ScreenshotMediaStatsToday => Localize("ScreenshotMediaStatsToday");
    public static string ScreenshotMediaStatsFavorites => Localize("ScreenshotMediaStatsFavorites");
    public static string ScreenshotMediaStatsScreenshots => Localize("ScreenshotMediaStatsScreenshots");
    public static string ScreenshotMediaSearch => Localize("ScreenshotMediaSearch");
    public static string ScreenshotMediaFilter => Localize("ScreenshotMediaFilter");
    public static string ScreenshotMediaPageSize => Localize("ScreenshotMediaPageSize");
    public static string ScreenshotMediaEmptyTitle => Localize("ScreenshotMediaEmptyTitle");
    public static string ScreenshotMediaEmptyHint => Localize("ScreenshotMediaEmptyHint");
    public static string ScreenshotMediaPrevious => Localize("ScreenshotMediaPrevious");
    public static string ScreenshotMediaNext => Localize("ScreenshotMediaNext");
    public static string ScreenshotMediaLoading => Localize("ScreenshotMediaLoading");
    public static string ScreenshotCopyImage => Localize("ScreenshotCopyImage");
    public static string ScreenshotCopyText => Localize("ScreenshotCopyText");
    public static string ScreenshotFavorite => Localize("ScreenshotFavorite");
    public static string ScreenshotDelete => Localize("ScreenshotDelete");
    public static string ScreenshotDetailTitle => Localize("ScreenshotDetailTitle");
    public static string ScreenshotClose => Localize("ScreenshotClose");
    public static string ScreenshotImageUnavailable => Localize("ScreenshotImageUnavailable");
    public static string ScreenshotOriginal => Localize("ScreenshotOriginal");
    public static string ScreenshotTranslatedImage => Localize("ScreenshotTranslatedImage");
    public static string ScreenshotResolution => Localize("ScreenshotResolution");
    public static string ScreenshotFileSize => Localize("ScreenshotFileSize");
    public static string ScreenshotCharacters => Localize("ScreenshotCharacters");
    public static string ScreenshotFavoriteStatus => Localize("ScreenshotFavoriteStatus");
    public static string ScreenshotFavorited => Localize("ScreenshotFavorited");
    public static string ScreenshotNotFavorited => Localize("ScreenshotNotFavorited");
    public static string ScreenshotOcrTab => Localize("ScreenshotOcrTab");
    public static string ScreenshotRefinedTab => Localize("ScreenshotRefinedTab");
    public static string ScreenshotTranslationTab => Localize("ScreenshotTranslationTab");
    public static string ScreenshotSummaryTab => Localize("ScreenshotSummaryTab");
    public static string ScreenshotSaveAs => Localize("ScreenshotSaveAs");
    public static string ScreenshotReveal => Localize("ScreenshotReveal");
    public static string ScreenshotReprocess => Localize("ScreenshotReprocess");
    public static string ScreenshotSaveDialogTitle => Localize("ScreenshotSaveDialogTitle");
    public static string ScreenshotPngFileFilter => Localize("ScreenshotPngFileFilter");
    public static string ScreenshotDefaultFileNamePrefix =>
        Localize("ScreenshotDefaultFileNamePrefix");
    public static string ScreenshotClipboardBusy => Localize("ScreenshotClipboardBusy");
    public static string ScreenshotClipboardFailed => Localize("ScreenshotClipboardFailed");
    public static string ScreenshotSaveFailed => Localize("ScreenshotSaveFailed");
    public static string HistoryDetailFailure => Localize("HistoryDetailFailure");

    public static string HistoryDetailProvider => Localize("HistoryDetailProvider");

    public static string HistoryDetailModel => Localize("HistoryDetailModel");

    public static string HistoryDetailContextSources =>
        Localize("HistoryDetailContextSources");

    public static string HistoryDetailTimeline => Localize("HistoryDetailTimeline");

    public static string HistoryDetailTools => Localize("HistoryDetailTools");

    public static string HistoryDetailArtifacts => Localize("HistoryDetailArtifacts");

    public static string HistoryDetailResultSummary =>
        Localize("HistoryDetailResultSummary");

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

    public static string SettingsHotkeyAgentSectionTitle =>
        Localize("SettingsHotkeyAgentSectionTitle");

    public static string SettingsHotkeyAgentSectionDescription =>
        Localize("SettingsHotkeyAgentSectionDescription");

    public static string SettingsHotkeyRecord => Localize("SettingsHotkeyRecord");

    public static string SettingsHotkeyModify => Localize("SettingsHotkeyModify");

    public static string SettingsHotkeyCancel => Localize("SettingsHotkeyCancel");

    public static string SettingsHotkeyClear => Localize("SettingsHotkeyClear");

    public static string SettingsHotkeyRestoreDefault =>
        Localize("SettingsHotkeyRestoreDefault");

    public static string SettingsHotkeyUnbound => Localize("SettingsHotkeyUnbound");

    public static string SettingsTextMaster => Localize("SettingsTextMaster");

    public static string SettingsTextMasterDescription =>
        Localize("SettingsTextMasterDescription");

    public static string SettingsTextSmartNumbers => Localize("SettingsTextSmartNumbers");

    public static string SettingsTextSmartNumbersDescription =>
        Localize("SettingsTextSmartNumbersDescription");

    public static string SettingsTextPunctuation => Localize("SettingsTextPunctuation");

    public static string SettingsTextPunctuationDescription =>
        Localize("SettingsTextPunctuationDescription");

    public static string SettingsTextLongSentences => Localize("SettingsTextLongSentences");

    public static string SettingsTextFillerWords => Localize("SettingsTextFillerWords");

    public static string SettingsTextCjkSpacing => Localize("SettingsTextCjkSpacing");

    public static string SettingsTextCapitalization => Localize("SettingsTextCapitalization");

    public static string SettingsTextDeterministicHeading =>
        Localize("SettingsTextDeterministicHeading");

    public static string SettingsTextDeterministicDescription =>
        Localize("SettingsTextDeterministicDescription");

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

    public static string SettingsCredentialShow => Localize("SettingsCredentialShow");

    public static string SettingsCredentialHide => Localize("SettingsCredentialHide");

    public static string SettingsCloudSelect => Localize("SettingsCloudSelect");

    public static string SettingsCloudSelectSucceeded =>
        Localize("SettingsCloudSelectSucceeded");

    public static string SettingsModelStatusSelected =>
        Localize("SettingsModelStatusSelected");

    public static string LlmProviderTitle => Localize("LlmProviderTitle");

    public static string LlmProviderSubtitle => Localize("LlmProviderSubtitle");

    public static string LlmProviderAdd => Localize("LlmProviderAdd");

    public static string LlmProviderEmpty => Localize("LlmProviderEmpty");

    public static string LlmProviderCurrent => Localize("LlmProviderCurrent");

    public static string LlmProviderEnable => Localize("LlmProviderEnable");

    public static string LlmProviderSetDefault => Localize("LlmProviderSetDefault");

    public static string LlmProviderEdit => Localize("LlmProviderEdit");

    public static string LlmProviderTestConnection =>
        Localize("LlmProviderTestConnection");

    public static string LlmProviderTestAgent => Localize("LlmProviderTestAgent");

    public static string LlmProviderDelete => Localize("LlmProviderDelete");

    public static string LlmProviderEditorHint => Localize("LlmProviderEditorHint");

    public static string LlmProviderTemplateLabel =>
        Localize("LlmProviderTemplateLabel");

    public static string LlmProviderName => Localize("LlmProviderName");

    public static string LlmProviderServiceUrl => Localize("LlmProviderServiceUrl");

    public static string LlmProviderModel => Localize("LlmProviderModel");

    public static string LlmProviderRefreshModels =>
        Localize("LlmProviderRefreshModels");

    public static string LlmProviderGenerationSettings =>
        Localize("LlmProviderGenerationSettings");

    public static string LlmProviderTemperature => Localize("LlmProviderTemperature");

    public static string LlmProviderTimeout => Localize("LlmProviderTimeout");

    public static string LlmProviderSeconds => Localize("LlmProviderSeconds");

    public static string LlmProviderApiKey => Localize("LlmProviderApiKey");

    public static string LlmProviderRevealApiKey =>
        Localize("LlmProviderRevealApiKey");

    public static string LlmProviderHideApiKey =>
        Localize("LlmProviderHideApiKey");

    public static string LlmProviderAddModel => Localize("LlmProviderAddModel");

    public static string LlmProviderGetApiKey => Localize("LlmProviderGetApiKey");

    public static string LlmProviderNoApiKeyRequired =>
        Localize("LlmProviderNoApiKeyRequired");

    public static string LlmProviderCredentialHint =>
        Localize("LlmProviderCredentialHint");

    public static string LlmProviderAvailability =>
        Localize("LlmProviderAvailability");

    public static string LlmProviderUseAsDefault =>
        Localize("LlmProviderUseAsDefault");

    public static string LlmProviderCancel => Localize("LlmProviderCancel");

    public static string LlmProviderSave => Localize("LlmProviderSave");

    public static string LlmProviderDeleteConfirmationTitle =>
        Localize("LlmProviderDeleteConfirmationTitle");

    public static string LlmProviderDeleteConfirmationMessage =>
        Localize("LlmProviderDeleteConfirmationMessage");

    public static string GlossaryImport => Localize("GlossaryImport");
    public static string GlossaryOpenFolder => Localize("GlossaryOpenFolder");
    public static string GlossaryTabHotwords => Localize("GlossaryTabHotwords");
    public static string GlossaryTabReplacements => Localize("GlossaryTabReplacements");
    public static string GlossarySearch => Localize("GlossarySearch");
    public static string GlossaryAdd => Localize("GlossaryAdd");
    public static string GlossarySuggestionsHeading => Localize("GlossarySuggestionsHeading");
    public static string GlossarySuggestionsDescription => Localize("GlossarySuggestionsDescription");
    public static string GlossarySuggestionAdd => Localize("GlossarySuggestionAdd");
    public static string GlossarySuggestionIgnore => Localize("GlossarySuggestionIgnore");
    public static string WritingStylesProfilesHeading => Localize("WritingStylesProfilesHeading");
    public static string WritingStylesAddProfile => Localize("WritingStylesAddProfile");
    public static string WritingStylesEditorHeading => Localize("WritingStylesEditorHeading");
    public static string WritingStylesNameLabel => Localize("WritingStylesNameLabel");
    public static string WritingStylesDescriptionLabel => Localize("WritingStylesDescriptionLabel");
    public static string WritingStylesApplicationsLabel => Localize("WritingStylesApplicationsLabel");
    public static string WritingStylesAutoMatch => Localize("WritingStylesAutoMatch");
    public static string WritingStylesInstructionLabel => Localize("WritingStylesInstructionLabel");
    public static string WritingStylesMarkdownLabel => Localize("WritingStylesMarkdownLabel");
    public static string WritingStylesPreviewHeading => Localize("WritingStylesPreviewHeading");
    public static string WritingStylesPreviewEmpty => Localize("WritingStylesPreviewEmpty");
    public static string WritingStylesRestore => Localize("WritingStylesRestore");
    public static string WritingStylesSave => Localize("WritingStylesSave");
    public static string SettingsScreenshotHotkeyHeading => Localize("SettingsScreenshotHotkeyHeading");
    public static string SettingsScreenshotHotkeyDescription => Localize("SettingsScreenshotHotkeyDescription");
    public static string SettingsScreenshotClipboardHeading => Localize("SettingsScreenshotClipboardHeading");
    public static string SettingsScreenshotClipboardDescription => Localize("SettingsScreenshotClipboardDescription");
    public static string SettingsScreenshotClipboardToggle => Localize("SettingsScreenshotClipboardToggle");
    public static string SettingsScreenshotClipboardToggleDescription =>
        Localize("SettingsScreenshotClipboardToggleDescription");
    public static string SettingsGeneralBasicsHeading => Localize("SettingsGeneralBasicsHeading");
    public static string SettingsGeneralBasicsDescription => Localize("SettingsGeneralBasicsDescription");
    public static string SettingsGeneralDarkThemeDescription => Localize("SettingsGeneralDarkThemeDescription");
    public static string SettingsGeneralLaunchAtLoginDescription =>
        Localize("SettingsGeneralLaunchAtLoginDescription");
    public static string SettingsGeneralPermissionsDescription =>
        Localize("SettingsGeneralPermissionsDescription");
    public static string SettingsGeneralDataDescription => Localize("SettingsGeneralDataDescription");
    public static string SettingsGeneralUiLanguage => Localize("SettingsGeneralUiLanguage");
    public static string SettingsGeneralUiLanguageDescription =>
        Localize("SettingsGeneralUiLanguageDescription");
    public static string SettingsGeneralUiLanguageSystem =>
        Localize("SettingsGeneralUiLanguageSystem");
    public static string SettingsGeneralGrayTrayIcon => Localize("SettingsGeneralGrayTrayIcon");
    public static string SettingsGeneralGrayTrayIconDescription =>
        Localize("SettingsGeneralGrayTrayIconDescription");
    public static string SettingsGeneralCapsLockIndicator =>
        Localize("SettingsGeneralCapsLockIndicator");
    public static string SettingsGeneralCapsLockIndicatorDescription =>
        Localize("SettingsGeneralCapsLockIndicatorDescription");
    public static string SettingsGeneralLocalModelsHeading =>
        Localize("SettingsGeneralLocalModelsHeading");
    public static string SettingsGeneralLocalModelsDescription =>
        Localize("SettingsGeneralLocalModelsDescription");
    public static string SettingsGeneralStreamPreview => Localize("SettingsGeneralStreamPreview");
    public static string SettingsGeneralStreamPreviewDescription =>
        Localize("SettingsGeneralStreamPreviewDescription");
    public static string SettingsGeneralAutoReleaseModels =>
        Localize("SettingsGeneralAutoReleaseModels");
    public static string SettingsGeneralAutoReleaseModelsDescription =>
        Localize("SettingsGeneralAutoReleaseModelsDescription");
    public static string SettingsVoiceDictationTitle => Localize("SettingsVoiceDictationTitle");
    public static string SettingsVoiceDictationDescription =>
        Localize("SettingsVoiceDictationDescription");
    public static string SettingsVoiceMiddleMouseDescription =>
        Localize("SettingsVoiceMiddleMouseDescription");
    public static string SettingsVoiceTriggerMode => Localize("SettingsVoiceTriggerMode");
    public static string SettingsVoiceTriggerModeHint => Localize("SettingsVoiceTriggerModeHint");
    public static string SettingsVoiceModify => Localize("SettingsVoiceModify");
    public static string SettingsVoiceModeHold => Localize("SettingsVoiceModeHold");
    public static string SettingsVoiceModeToggle => Localize("SettingsVoiceModeToggle");
    public static string SettingsSelectionSectionHeading =>
        Localize("SettingsSelectionSectionHeading");
    public static string SettingsSelectionSectionDescription =>
        Localize("SettingsSelectionSectionDescription");
    public static string ClipboardImageOcrNoImage => Localize("ClipboardImageOcrNoImage");
    public static string ClipboardImageOcrNoText => Localize("ClipboardImageOcrNoText");
    public static string ClipboardImageOcrDisabled => Localize("ClipboardImageOcrDisabled");
    public static string WritingStylesPerStyleAutoMatch => Localize("WritingStylesPerStyleAutoMatch");
    public static string WritingStylesRoutesEmpty => Localize("WritingStylesRoutesEmpty");
    public static string WritingStylesPreviewSample => Localize("WritingStylesPreviewSample");
    public static string WritingStylesBuiltInProtectedMessage =>
        Localize("WritingStylesBuiltInProtectedMessage");
    public static string WritingStyleEmailName => Localize("WritingStyleEmailName");
    public static string WritingStyleEmailDescription => Localize("WritingStyleEmailDescription");
    public static string WritingStyleMeetingName => Localize("WritingStyleMeetingName");
    public static string WritingStyleMeetingDescription => Localize("WritingStyleMeetingDescription");
    public static string WritingStyleTranslationName => Localize("WritingStyleTranslationName");
    public static string WritingStyleTranslationDescription =>
        Localize("WritingStyleTranslationDescription");
    public static string SettingsVoiceDeviceDefaultMarker =>
        Localize("SettingsVoiceDeviceDefaultMarker");
    public static string SettingsVoiceDeviceUnavailableMarker =>
        Localize("SettingsVoiceDeviceUnavailableMarker");
    public static string HelpUpdateIdle => Localize("HelpUpdateIdle");
    public static string HelpUpdateAvailable => Localize("HelpUpdateAvailable");
    public static string HelpUpdateUpToDate => Localize("HelpUpdateUpToDate");
    public static string HelpUpdateFailed => Localize("HelpUpdateFailed");
    public static string HelpUpdateOpenRelease => Localize("HelpUpdateOpenRelease");
    public static string NotesHistoryOnlySubtitle => Localize("NotesHistoryOnlySubtitle");

    public static string Localize(string key, CultureInfo? culture = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        return Resources.GetString(key, culture ?? CultureInfo.CurrentUICulture)
            ?? Resources.GetString(key, CultureInfo.InvariantCulture)
            ?? throw new MissingManifestResourceException(
                $"The localized resource '{key}' is missing.");
    }
}
