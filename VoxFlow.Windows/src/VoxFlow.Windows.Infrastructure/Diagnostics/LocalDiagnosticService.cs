using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using VoxFlow.Windows.Application.Diagnostics;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Diagnostics;

public sealed class LocalDiagnosticService : IDiagnosticService, IDisposable, IAsyncDisposable
{
    private static readonly string[] SensitiveMarkers =
    [
        "audio",
        "transcript",
        "prompt",
        "response",
        "authorization",
        "api key",
        "secret",
        "token",
    ];

    private static readonly JsonSerializerOptions SerializerOptions = CreateSerializerOptions();

    private readonly DiagnosticPrivacyPolicy privacyPolicy;
    private readonly SemaphoreSlim ioGate = new(1, 1);
    private readonly object lifetimeGate = new();
    private readonly TaskCompletionSource lifetimeDrained = new(
        TaskCreationOptions.RunContinuationsAsynchronously);
    private int activeOperationCount;
    private bool disposalRequested;
    private bool ioGateDisposed;

    public LocalDiagnosticService(
        string logDirectory,
        DiagnosticPrivacyPolicy? privacyPolicy = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(logDirectory);

        Directory.CreateDirectory(logDirectory);
        LogPath = Path.Combine(logDirectory, "voxflow.ndjson");
        this.privacyPolicy = privacyPolicy ?? new DiagnosticPrivacyPolicy();
    }

    public string LogPath { get; }

    public async ValueTask RecordAsync(
        DiagnosticEvent diagnosticEvent,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(diagnosticEvent);
        EnterOperation();

        try
        {
            if (!privacyPolicy.IsAllowed(DiagnosticDestination.LocalLog, userInitiated: false))
            {
                throw new InvalidOperationException("Local diagnostics are disabled by policy.");
            }

            var line = JsonSerializer.Serialize(Sanitize(diagnosticEvent), SerializerOptions);
            await ioGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                await File.AppendAllTextAsync(
                    LogPath,
                    line + Environment.NewLine,
                    new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
                    cancellationToken).ConfigureAwait(false);
            }
            finally
            {
                ioGate.Release();
            }
        }
        finally
        {
            ExitOperation();
        }
    }

    public async ValueTask<string> CreateManualReportAsync(
        DiagnosticReportRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        EnterOperation();

        try
        {
            if (!privacyPolicy.IsAllowed(
                    DiagnosticDestination.UserClipboard,
                    request.UserInitiated))
            {
                throw new InvalidOperationException(
                    "A diagnostic report can only be created by an explicit user action.");
            }

            await ioGate.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                return File.Exists(LogPath)
                    ? await File.ReadAllTextAsync(LogPath, cancellationToken).ConfigureAwait(false)
                    : string.Empty;
            }
            finally
            {
                ioGate.Release();
            }
        }
        finally
        {
            ExitOperation();
        }
    }

    public void Dispose() => DisposeAsync().AsTask().GetAwaiter().GetResult();

    public async ValueTask DisposeAsync()
    {
        Task drainTask;
        lock (lifetimeGate)
        {
            if (ioGateDisposed)
            {
                return;
            }

            disposalRequested = true;
            if (activeOperationCount == 0)
            {
                lifetimeDrained.TrySetResult();
            }

            drainTask = lifetimeDrained.Task;
        }

        await drainTask.ConfigureAwait(false);

        var shouldDisposeGate = false;
        lock (lifetimeGate)
        {
            if (!ioGateDisposed)
            {
                ioGateDisposed = true;
                shouldDisposeGate = true;
            }
        }

        if (shouldDisposeGate)
        {
            ioGate.Dispose();
        }

        GC.SuppressFinalize(this);
    }

    private static SanitizedDiagnosticEvent Sanitize(DiagnosticEvent source) => new(
        source.Timestamp.ToUniversalTime(),
        source.Kind,
        source.Provider,
        source.Stage,
        source.ErrorCode,
        source.Duration?.TotalMilliseconds,
        SanitizeModelId(source.ModelId),
        source.AudioFrameCount,
        source.DroppedFrameCount,
        SanitizeAppVersion(source.AppVersion));

    private static string? SanitizeModelId(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)
            || value.Length > 128
            || IsCredentialShaped(value)
            || SensitiveMarkers.Any(marker =>
                value.Contains(marker, StringComparison.OrdinalIgnoreCase))
            || value.Any(character =>
                !(char.IsAsciiLetterOrDigit(character)
                    || character is '.' or '-' or '_' or ':')))
        {
            return null;
        }

        return value;
    }

    private static string SanitizeAppVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 48)
        {
            return "unknown";
        }

        var pieces = value.Split('-', 2, StringSplitOptions.None);
        var numericParts = pieces[0].Split('.', StringSplitOptions.None);
        if (numericParts.Length is < 2 or > 4
            || numericParts.Any(part =>
                part.Length is < 1 or > 5
                || !part.All(char.IsAsciiDigit)))
        {
            return "unknown";
        }

        if (pieces.Length == 2
            && (pieces[1].Length is < 1 or > 24
                || pieces[1].Any(character =>
                    !(char.IsAsciiLetterOrDigit(character)
                        || character is '.' or '-'))))
        {
            return "unknown";
        }

        return value;
    }

    private static bool IsCredentialShaped(string value)
    {
        if ((value.StartsWith("sk-", StringComparison.OrdinalIgnoreCase)
                || value.StartsWith("AKID", StringComparison.OrdinalIgnoreCase))
            && value.Length >= 20)
        {
            return true;
        }

        if (value.Length >= 32 && value.All(IsBase64UrlCharacter))
        {
            return true;
        }

        var jwtParts = value.Split('.', StringSplitOptions.None);
        return jwtParts.Length == 3
            && jwtParts.All(part =>
                part.Length >= 16 && part.All(IsBase64UrlCharacter));
    }

    private static bool IsBase64UrlCharacter(char character) =>
        char.IsAsciiLetterOrDigit(character) || character is '-' or '_';

    private void EnterOperation()
    {
        lock (lifetimeGate)
        {
            ObjectDisposedException.ThrowIf(disposalRequested, this);
            activeOperationCount++;
        }
    }

    private void ExitOperation()
    {
        lock (lifetimeGate)
        {
            activeOperationCount--;
            if (disposalRequested && activeOperationCount == 0)
            {
                lifetimeDrained.TrySetResult();
            }
        }
    }

    private static JsonSerializerOptions CreateSerializerOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false,
        };
        options.Converters.Add(
            new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        return options;
    }

    private sealed record SanitizedDiagnosticEvent(
        DateTimeOffset Timestamp,
        DiagnosticEventKind Kind,
        AsrProviderId? Provider,
        DiagnosticStage? Stage,
        VoxFlowErrorCode? ErrorCode,
        double? DurationMilliseconds,
        string? ModelId,
        long? AudioFrameCount,
        long? DroppedFrameCount,
        string AppVersion);
}
