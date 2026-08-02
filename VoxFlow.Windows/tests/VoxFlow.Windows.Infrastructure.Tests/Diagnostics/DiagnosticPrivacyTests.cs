using System.Text.Json;
using VoxFlow.Windows.Application.Diagnostics;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Diagnostics;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Diagnostics;

public sealed class DiagnosticPrivacyTests
{
    public static TheoryData<string> SensitiveValues => new()
    {
        "raw-audio-sentinel-734",
        "full-transcript-sentinel-734",
        "private-prompt-sentinel-734",
        "provider-response-sentinel-734",
        "Authorization-sentinel-734",
        "API Key sentinel 734",
        "Secret-sentinel-734",
        "Token-sentinel-734",
    };

    public static TheoryData<string> CredentialShapedValues => new()
    {
        string.Concat("s", "k", "-", new string('A', 40)),
        string.Concat("AK", "ID", new string('B', 28)),
        new string('C', 48),
        string.Join('.', new string('D', 24), new string('E', 32), new string('F', 24)),
    };

    [Theory]
    [MemberData(nameof(SensitiveValues))]
    public async Task Sensitive_untrusted_values_never_reach_local_or_manual_reports(
        string sensitiveValue)
    {
        using var directory = new TemporaryDirectory();
        var service = new LocalDiagnosticService(directory.Path);
        var diagnosticEvent = CreateEvent(modelId: sensitiveValue);

        await service.RecordAsync(diagnosticEvent, CancellationToken.None);
        var manualReport = await service.CreateManualReportAsync(
            new DiagnosticReportRequest(UserInitiated: true),
            CancellationToken.None);
        var localReport = File.ReadAllText(service.LogPath);

        Assert.DoesNotContain(sensitiveValue, localReport, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(sensitiveValue, manualReport, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [MemberData(nameof(CredentialShapedValues))]
    public async Task Credential_shaped_values_never_reach_any_diagnostic_destination(
        string credentialShapedValue)
    {
        using var directory = new TemporaryDirectory();
        var service = new LocalDiagnosticService(directory.Path);
        var diagnosticEvent = CreateEvent(credentialShapedValue) with
        {
            AppVersion = credentialShapedValue,
        };

        await service.RecordAsync(diagnosticEvent, CancellationToken.None);

        var localReport = File.ReadAllText(service.LogPath);
        var manualReport = await service.CreateManualReportAsync(
            new DiagnosticReportRequest(UserInitiated: true),
            CancellationToken.None);
        Assert.DoesNotContain(
            credentialShapedValue,
            localReport,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            credentialShapedValue,
            manualReport,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Local_and_manual_reports_share_the_same_whitelisted_event_shape()
    {
        using var directory = new TemporaryDirectory();
        var service = new LocalDiagnosticService(directory.Path);
        var diagnosticEvent = CreateEvent(modelId: "qwen3-asr-0.6b");

        await service.RecordAsync(diagnosticEvent, CancellationToken.None);

        var localLine = File.ReadAllText(service.LogPath).Trim();
        var manualLine = (await service.CreateManualReportAsync(
            new DiagnosticReportRequest(UserInitiated: true),
            CancellationToken.None)).Trim();
        using var document = JsonDocument.Parse(localLine);
        var names = document.RootElement
            .EnumerateObject()
            .Select(property => property.Name)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(localLine, manualLine);
        Assert.Equal(
            [
                "appVersion",
                "audioFrameCount",
                "droppedFrameCount",
                "durationMilliseconds",
                "errorCode",
                "kind",
                "modelId",
                "provider",
                "stage",
                "timestamp",
            ],
            names);
        Assert.DoesNotContain("message", localLine, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("exception", localLine, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("endpoint", localLine, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Diagnostics_allow_local_logs_and_only_user_initiated_clipboard_reports()
    {
        var policy = new DiagnosticPrivacyPolicy();

        Assert.True(policy.IsAllowed(DiagnosticDestination.LocalLog, userInitiated: false));
        Assert.True(policy.IsAllowed(DiagnosticDestination.UserClipboard, userInitiated: true));
        Assert.False(policy.IsAllowed(DiagnosticDestination.UserClipboard, userInitiated: false));
        Assert.False(policy.IsAllowed(DiagnosticDestination.Telemetry, userInitiated: true));
        Assert.False(policy.IsAllowed(DiagnosticDestination.CrashReport, userInitiated: true));

        using var directory = new TemporaryDirectory();
        var service = new LocalDiagnosticService(directory.Path, policy);
        await service.RecordAsync(CreateEvent("qwen3-asr-0.6b"), CancellationToken.None);

        await Assert.ThrowsAsync<InvalidOperationException>(async () =>
            await service.CreateManualReportAsync(
                new DiagnosticReportRequest(UserInitiated: false),
                CancellationToken.None));
    }

    [Fact]
    public async Task Multiple_events_remain_local_and_manual_export_requires_an_explicit_call()
    {
        using var directory = new TemporaryDirectory();
        var service = new LocalDiagnosticService(directory.Path);

        await service.RecordAsync(CreateEvent("qwen3-asr-0.6b"), CancellationToken.None);
        await service.RecordAsync(
            CreateEvent("qwen3-asr-1.7b") with
            {
                Kind = DiagnosticEventKind.DictationCompleted,
                ErrorCode = null,
            },
            CancellationToken.None);

        Assert.True(File.Exists(service.LogPath));
        Assert.Equal(2, File.ReadLines(service.LogPath).Count());

        var report = await service.CreateManualReportAsync(
            new DiagnosticReportRequest(UserInitiated: true),
            CancellationToken.None);
        Assert.Equal(2, report.Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries).Length);
    }

    [Fact]
    public async Task Disposal_waits_for_accepted_writes_exports_and_cancellation_before_closing_io()
    {
        using var directory = new TemporaryDirectory();
        var service = new LocalDiagnosticService(directory.Path);
        const int writeCount = 64;

        var writes = Enumerable.Range(0, writeCount)
            .Select(index => service.RecordAsync(
                CreateEvent($"qwen3-asr-{index}"),
                CancellationToken.None).AsTask())
            .ToArray();
        var export = service.CreateManualReportAsync(
            new DiagnosticReportRequest(UserInitiated: true),
            CancellationToken.None).AsTask();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var cancelledWrite = service.RecordAsync(
            CreateEvent("qwen3-asr-cancelled"),
            cancellation.Token).AsTask();

        var disposal = service.DisposeAsync().AsTask();

        await Task.WhenAll(writes);
        await export;
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cancelledWrite);
        await disposal;

        Assert.Equal(writeCount, File.ReadLines(service.LogPath).Count());
        await Assert.ThrowsAsync<ObjectDisposedException>(async () =>
            await service.RecordAsync(CreateEvent("qwen3-asr-late"), CancellationToken.None));
        await Assert.ThrowsAsync<ObjectDisposedException>(async () =>
            await service.CreateManualReportAsync(
                new DiagnosticReportRequest(UserInitiated: true),
                CancellationToken.None));
    }

    [Fact]
    public async Task Safe_model_and_version_identifiers_are_preserved()
    {
        using var directory = new TemporaryDirectory();
        await using var service = new LocalDiagnosticService(directory.Path);

        await service.RecordAsync(
            CreateEvent("qwen3-asr-0.6b") with { AppVersion = "1.2.3-preview.4" },
            CancellationToken.None);

        using var document = JsonDocument.Parse(File.ReadAllText(service.LogPath));
        Assert.Equal("qwen3-asr-0.6b", document.RootElement.GetProperty("modelId").GetString());
        Assert.Equal("1.2.3-preview.4", document.RootElement.GetProperty("appVersion").GetString());
    }

    private static DiagnosticEvent CreateEvent(string modelId) => new(
        new DateTimeOffset(2026, 7, 10, 12, 0, 0, TimeSpan.Zero),
        DiagnosticEventKind.DictationFailed,
        AsrProviderId.TencentCloud,
        DiagnosticStage.WaitingForFinal,
        VoxFlowErrorCode.NetworkFailure,
        TimeSpan.FromMilliseconds(125),
        modelId,
        AudioFrameCount: 42,
        DroppedFrameCount: 2,
        AppVersion: "1.0.0");
}
