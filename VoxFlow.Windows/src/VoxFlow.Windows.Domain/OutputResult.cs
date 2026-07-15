using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum OutputResultKind
{
    [JsonStringEnumMemberName("inserted")]
    Inserted,

    [JsonStringEnumMemberName("copied")]
    Copied,

    [JsonStringEnumMemberName("targetChanged")]
    TargetChanged,

    [JsonStringEnumMemberName("permissionDenied")]
    PermissionDenied,

    [JsonStringEnumMemberName("injectionFailed")]
    InjectionFailed,

    [JsonStringEnumMemberName("copyFailed")]
    CopyFailed,

    [JsonStringEnumMemberName("cancelled")]
    Cancelled,
}

public sealed record OutputResult
{
    private static readonly IReadOnlyDictionary<OutputResultKind, VoxFlowErrorCode> RequiredErrors =
        new Dictionary<OutputResultKind, VoxFlowErrorCode>
        {
            [OutputResultKind.TargetChanged] = VoxFlowErrorCode.TargetChanged,
            [OutputResultKind.PermissionDenied] = VoxFlowErrorCode.InputPermissionDenied,
            [OutputResultKind.InjectionFailed] = VoxFlowErrorCode.InputInjectionFailure,
            [OutputResultKind.CopyFailed] = VoxFlowErrorCode.ClipboardFailure,
        };

    [JsonConstructor]
    public OutputResult(OutputResultKind kind, VoxFlowErrorCode? errorCode = null)
    {
        if (RequiredErrors.TryGetValue(kind, out var requiredError))
        {
            if (errorCode != requiredError)
            {
                throw new ArgumentException(
                    $"Output result {kind} requires error code {requiredError}.",
                    nameof(errorCode));
            }
        }
        else if (errorCode is not null)
        {
            throw new ArgumentException(
                $"Output result {kind} cannot carry an error code.",
                nameof(errorCode));
        }

        Kind = kind;
        ErrorCode = errorCode;
    }

    public OutputResultKind Kind { get; }

    public VoxFlowErrorCode? ErrorCode { get; }
}
