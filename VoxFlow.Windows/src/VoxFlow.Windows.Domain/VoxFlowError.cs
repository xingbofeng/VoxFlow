using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum VoxFlowErrorCode
{
    [JsonStringEnumMemberName("asrNotConfigured")]
    AsrNotConfigured,

    [JsonStringEnumMemberName("microphonePermissionDenied")]
    MicrophonePermissionDenied,

    [JsonStringEnumMemberName("audioDeviceUnavailable")]
    AudioDeviceUnavailable,

    [JsonStringEnumMemberName("audioFormatInvalid")]
    AudioFormatInvalid,

    [JsonStringEnumMemberName("networkFailure")]
    NetworkFailure,

    [JsonStringEnumMemberName("authenticationFailed")]
    AuthenticationFailed,

    [JsonStringEnumMemberName("quotaExceeded")]
    QuotaExceeded,

    [JsonStringEnumMemberName("providerFailure")]
    ProviderFailure,

    [JsonStringEnumMemberName("finalTimeout")]
    FinalTimeout,

    [JsonStringEnumMemberName("emptyFinal")]
    EmptyFinal,

    [JsonStringEnumMemberName("modelNotReady")]
    ModelNotReady,

    [JsonStringEnumMemberName("nativeRuntimeFailure")]
    NativeRuntimeFailure,

    [JsonStringEnumMemberName("targetChanged")]
    TargetChanged,

    [JsonStringEnumMemberName("clipboardFailure")]
    ClipboardFailure,

    [JsonStringEnumMemberName("inputPermissionDenied")]
    InputPermissionDenied,

    [JsonStringEnumMemberName("inputInjectionFailure")]
    InputInjectionFailure,

    [JsonStringEnumMemberName("unknown")]
    Unknown,
}

public enum VoxFlowErrorCategory
{
    [JsonStringEnumMemberName("configuration")]
    Configuration,

    [JsonStringEnumMemberName("permission")]
    Permission,

    [JsonStringEnumMemberName("audio")]
    Audio,

    [JsonStringEnumMemberName("network")]
    Network,

    [JsonStringEnumMemberName("provider")]
    Provider,

    [JsonStringEnumMemberName("model")]
    Model,

    [JsonStringEnumMemberName("output")]
    Output,

    [JsonStringEnumMemberName("system")]
    System,
}

public sealed record VoxFlowError(
    VoxFlowErrorCode Code,
    AsrProviderId? Provider = null);

public sealed record VoxFlowErrorClassification(
    VoxFlowErrorCategory Category,
    bool IsRetryable);

public static class VoxFlowErrorExtensions
{
    public static VoxFlowErrorClassification Classify(this VoxFlowError error)
    {
        ArgumentNullException.ThrowIfNull(error);

        return error.Code switch
        {
            VoxFlowErrorCode.AsrNotConfigured => Classification(
                VoxFlowErrorCategory.Configuration,
                false),
            VoxFlowErrorCode.MicrophonePermissionDenied or
                VoxFlowErrorCode.InputPermissionDenied => Classification(
                    VoxFlowErrorCategory.Permission,
                    false),
            VoxFlowErrorCode.AudioDeviceUnavailable => Classification(
                VoxFlowErrorCategory.Audio,
                true),
            VoxFlowErrorCode.AudioFormatInvalid => Classification(
                VoxFlowErrorCategory.Audio,
                false),
            VoxFlowErrorCode.NetworkFailure => Classification(
                VoxFlowErrorCategory.Network,
                true),
            VoxFlowErrorCode.AuthenticationFailed or
                VoxFlowErrorCode.QuotaExceeded => Classification(
                    VoxFlowErrorCategory.Provider,
                    false),
            VoxFlowErrorCode.ProviderFailure or
                VoxFlowErrorCode.FinalTimeout or
                VoxFlowErrorCode.EmptyFinal => Classification(
                    VoxFlowErrorCategory.Provider,
                    true),
            VoxFlowErrorCode.ModelNotReady => Classification(
                VoxFlowErrorCategory.Model,
                false),
            VoxFlowErrorCode.NativeRuntimeFailure => Classification(
                VoxFlowErrorCategory.Model,
                true),
            VoxFlowErrorCode.TargetChanged => Classification(
                VoxFlowErrorCategory.Output,
                false),
            VoxFlowErrorCode.ClipboardFailure or
                VoxFlowErrorCode.InputInjectionFailure => Classification(
                    VoxFlowErrorCategory.Output,
                    true),
            _ => Classification(VoxFlowErrorCategory.System, false),
        };
    }

    private static VoxFlowErrorClassification Classification(
        VoxFlowErrorCategory category,
        bool retryable) => new(category, retryable);
}
