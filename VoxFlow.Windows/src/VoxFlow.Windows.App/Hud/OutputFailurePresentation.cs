using System.Globalization;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Hud;

public enum OutputRecoveryAction
{
    None,
    RestartAsAdministrator,
    OpenModels,
    OpenMicrophonePrivacy,
    RetryProvider,
    RetryQwen,
}

public sealed record OutputFailurePresentation(
    string Message,
    OutputRecoveryAction RecoveryAction,
    bool CanCopyDiagnostics = true,
    bool IsFallback = false)
{
    public static OutputFailurePresentation From(
        OutputResult result,
        CultureInfo? culture = null)
    {
        ArgumentNullException.ThrowIfNull(result);
        return From(result.ErrorCode ?? VoxFlowErrorCode.Unknown, culture);
    }

    public static OutputFailurePresentation From(
        VoxFlowErrorCode errorCode,
        CultureInfo? culture = null) => errorCode switch
        {
            VoxFlowErrorCode.InputPermissionDenied => new(
                L10n.Localize("OutputPermissionDenied", culture),
                OutputRecoveryAction.RestartAsAdministrator),
            VoxFlowErrorCode.InputInjectionFailure => new(
                L10n.Localize("OutputInjectionFailed", culture),
                OutputRecoveryAction.None),
            VoxFlowErrorCode.TargetChanged => new(
                L10n.Localize("OutputTargetChanged", culture),
                OutputRecoveryAction.None),
            VoxFlowErrorCode.ClipboardFailure => new(
                L10n.Localize("OutputClipboardFailed", culture),
                OutputRecoveryAction.None),
            _ => new(
                L10n.Localize("HudGenericFailure", culture),
                OutputRecoveryAction.None),
        };

    public static OutputFailurePresentation From(
        VoxFlowError error,
        bool llmFallback,
        CultureInfo? culture = null)
    {
        ArgumentNullException.ThrowIfNull(error);
        if (llmFallback)
        {
            return new OutputFailurePresentation(
                L10n.Localize("FailureLlmFallback", culture),
                OutputRecoveryAction.None,
                CanCopyDiagnostics: true,
                IsFallback: true);
        }

        return error.Code switch
        {
            VoxFlowErrorCode.AsrNotConfigured or VoxFlowErrorCode.ModelNotReady => new(
                L10n.Localize("FailureAsrUnavailable", culture),
                OutputRecoveryAction.OpenModels),
            VoxFlowErrorCode.MicrophonePermissionDenied => new(
                L10n.Localize("FailureMicrophonePermission", culture),
                OutputRecoveryAction.OpenMicrophonePrivacy),
            VoxFlowErrorCode.ProviderFailure or VoxFlowErrorCode.NetworkFailure or
                VoxFlowErrorCode.AuthenticationFailed or VoxFlowErrorCode.QuotaExceeded or
                VoxFlowErrorCode.FinalTimeout => new(
                    L10n.Localize("FailureCloudProvider", culture),
                    OutputRecoveryAction.RetryProvider),
            VoxFlowErrorCode.NativeRuntimeFailure => new(
                L10n.Localize("FailureQwenRuntime", culture),
                OutputRecoveryAction.RetryQwen),
            _ => From(error.Code, culture),
        };
    }
}
