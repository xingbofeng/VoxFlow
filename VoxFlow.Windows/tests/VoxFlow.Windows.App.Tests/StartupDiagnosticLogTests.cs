using System.IO;
using System.Text.Json;
using VoxFlow.Windows.App.Diagnostics;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class StartupDiagnosticLogTests
{
    [Fact]
    public void Records_startup_stage_and_exception_as_ndjson()
    {
        using var directory = new TemporaryDirectory();
        var logPath = Path.Combine(directory.Path, "logs", "startup.ndjson");
        var log = new StartupDiagnosticLog(logPath);

        log.Record("startup.begin");
        log.Record("startup.failed", new InvalidOperationException("database unavailable"));

        var lines = File.ReadAllLines(logPath);
        Assert.Equal(2, lines.Length);

        using var started = JsonDocument.Parse(lines[0]);
        Assert.Equal("startup.begin", started.RootElement.GetProperty("eventName").GetString());
        Assert.Equal("VoxFlow", started.RootElement.GetProperty("application").GetString());

        using var failed = JsonDocument.Parse(lines[1]);
        Assert.Equal("startup.failed", failed.RootElement.GetProperty("eventName").GetString());
        Assert.Equal(
            typeof(InvalidOperationException).FullName,
            failed.RootElement.GetProperty("exceptionType").GetString());
        Assert.Equal(
            "database unavailable",
            failed.RootElement.GetProperty("exceptionMessage").GetString());
    }

    [Fact]
    public void Logging_failure_never_masks_the_original_startup_failure()
    {
        using var directory = new TemporaryDirectory();
        var blockingFile = Path.Combine(directory.Path, "not-a-directory");
        File.WriteAllText(blockingFile, "occupied");
        var log = new StartupDiagnosticLog(Path.Combine(blockingFile, "startup.ndjson"));

        var error = Record.Exception(() =>
            log.Record("startup.failed", new InvalidOperationException("original")));

        Assert.Null(error);
    }

    [Fact]
    public void Crash_diagnostics_redact_known_credential_shapes_from_message_and_stack_text()
    {
        using var directory = new TemporaryDirectory();
        var logPath = Path.Combine(directory.Path, "logs", "startup.ndjson");
        var log = new StartupDiagnosticLog(logPath);
        const string apiKey = "sk-" + "diagnostic-fixture-1234567890";
        const string bearer = "Bearer" + " diagnostic-token-1234567890";

        log.Record("startup.failed", new InvalidOperationException(
            $"apiKey={apiKey}; authorization={bearer}"));

        var content = File.ReadAllText(logPath);
        Assert.DoesNotContain(apiKey, content, StringComparison.Ordinal);
        Assert.DoesNotContain("diagnostic-token-1234567890", content, StringComparison.Ordinal);
        Assert.Contains("[REDACTED]", content, StringComparison.Ordinal);
    }

    [Fact]
    public void Manual_report_redacts_tampered_log_content_before_it_reaches_the_clipboard()
    {
        using var directory = new TemporaryDirectory();
        var logPath = Path.Combine(directory.Path, "logs", "startup.ndjson");
        Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
        const string bearer = "Bearer" + " synthetic-diagnostic-token-1234567890";
        File.WriteAllText(
            logPath,
            "authorization=" + bearer);
        var log = new StartupDiagnosticLog(logPath);

        var report = log.CreateSanitizedReport();

        Assert.DoesNotContain("synthetic-diagnostic-token", report, StringComparison.Ordinal);
        Assert.Contains("[REDACTED]", report, StringComparison.Ordinal);
    }
}
