using System.Text.Json.Serialization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Diagnostics;

public enum DiagnosticEventKind
{
    [JsonStringEnumMemberName("dictationStarted")]
    DictationStarted,

    [JsonStringEnumMemberName("dictationCompleted")]
    DictationCompleted,

    [JsonStringEnumMemberName("dictationFailed")]
    DictationFailed,

    [JsonStringEnumMemberName("modelStateChanged")]
    ModelStateChanged,
}

public enum DiagnosticStage
{
    [JsonStringEnumMemberName("preparing")]
    Preparing,

    [JsonStringEnumMemberName("recording")]
    Recording,

    [JsonStringEnumMemberName("waitingForFinal")]
    WaitingForFinal,

    [JsonStringEnumMemberName("processing")]
    Processing,

    [JsonStringEnumMemberName("injecting")]
    Injecting,
}

public sealed record DiagnosticEvent(
    DateTimeOffset Timestamp,
    DiagnosticEventKind Kind,
    AsrProviderId? Provider,
    DiagnosticStage? Stage,
    VoxFlowErrorCode? ErrorCode,
    TimeSpan? Duration,
    string? ModelId,
    long? AudioFrameCount,
    long? DroppedFrameCount,
    string AppVersion);

public enum DiagnosticDestination
{
    LocalLog,
    UserClipboard,
    Telemetry,
    CrashReport,
}

public sealed record DiagnosticReportRequest(bool UserInitiated);

public sealed class DiagnosticPrivacyPolicy
{
    public bool IsAllowed(
        DiagnosticDestination destination,
        bool userInitiated) => destination switch
        {
            DiagnosticDestination.LocalLog => true,
            DiagnosticDestination.UserClipboard => userInitiated,
            DiagnosticDestination.Telemetry => false,
            DiagnosticDestination.CrashReport => false,
            _ => false,
        };
}

public interface IDiagnosticService
{
    ValueTask RecordAsync(
        DiagnosticEvent diagnosticEvent,
        CancellationToken cancellationToken);

    ValueTask<string> CreateManualReportAsync(
        DiagnosticReportRequest request,
        CancellationToken cancellationToken);
}
