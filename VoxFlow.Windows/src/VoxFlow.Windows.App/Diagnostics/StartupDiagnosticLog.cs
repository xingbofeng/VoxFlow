using System.IO;
using System.Diagnostics.CodeAnalysis;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace VoxFlow.Windows.App.Diagnostics;

/// <summary>
/// Best-effort process-startup diagnostics. Logging must never replace the
/// exception that caused startup to fail.
/// </summary>
public sealed class StartupDiagnosticLog
{
    private const int MaximumManualReportCharacters = 200_000;
    private static readonly UTF8Encoding Utf8WithoutBom = new(false);
    private static readonly Regex SensitiveDiagnosticValue = new(
        "(?ix)\\bsk-[a-z0-9._-]{16,}"
        + "|\\bAKID[a-z0-9]{16,}"
        + "|\\bbearer\\s+[a-z0-9._-]{8,}"
        + "|(?<=(?:api[_-]?key|secret[_-]?(?:id|key)|access[_-]?token|authorization|bearer[_-]?token)\\s*[:=]\\s*[\\\"']?)[^\\s\\\"',}\\]]{8,}",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private readonly object writeGate = new();

    public StartupDiagnosticLog(string logPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(logPath);
        LogPath = logPath;
    }

    public string LogPath { get; }

    public static string DefaultLogPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VoxFlow",
        "logs",
        "startup.ndjson");

    [SuppressMessage(
        "Design",
        "CA1031:Do not catch general exception types",
        Justification = "Crash logging must never mask the original application failure.")]
    public void Record(string eventName, Exception? exception = null)
    {
        try
        {
            var entry = new
            {
                timestampUtc = DateTimeOffset.UtcNow,
                application = "VoxFlow",
                applicationVersion = typeof(StartupDiagnosticLog).Assembly
                    .GetName()
                    .Version?
                    .ToString(),
                processId = Environment.ProcessId,
                eventName,
                exceptionType = exception?.GetType().FullName,
                exceptionMessage = Sanitize(exception?.Message),
                exception = Sanitize(exception?.ToString()),
            };
            var line = JsonSerializer.Serialize(entry);

            lock (writeGate)
            {
                var directory = Path.GetDirectoryName(LogPath);
                if (!string.IsNullOrWhiteSpace(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                File.AppendAllText(
                    LogPath,
                    line + Environment.NewLine,
                    Utf8WithoutBom);
            }
        }
        catch
        {
            // Startup diagnostics are intentionally best effort. The original
            // application exception must remain the observable failure.
        }
    }

    [SuppressMessage(
        "Design",
        "CA1031:Do not catch general exception types",
        Justification = "Manual diagnostics must never crash the settings UI.")]
    public string CreateSanitizedReport()
    {
        try
        {
            lock (writeGate)
            {
                if (!File.Exists(LogPath))
                {
                    return string.Empty;
                }

                var content = File.ReadAllText(LogPath, Encoding.UTF8);
                if (content.Length > MaximumManualReportCharacters)
                {
                    content = content[^MaximumManualReportCharacters..];
                }
                return Sanitize(content) ?? string.Empty;
            }
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string? Sanitize(string? value) => value is null
        ? null
        : SensitiveDiagnosticValue.Replace(value, "[REDACTED]");
}
