using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentTraceSanitizationResult(
    AgentActionTrace Trace,
    int SourceSchemaVersion,
    SchemaCompatibility SourceCompatibility);

public sealed class AgentTraceSanitizationContext
{
    public AgentTraceSanitizationContext(
        IReadOnlyCollection<string>? knownSecrets = null,
        IReadOnlyCollection<string>? homeDirectories = null)
    {
        KnownSecrets = Array.AsReadOnly((knownSecrets ?? [])
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToArray());
        HomeDirectories = Array.AsReadOnly((homeDirectories ?? [])
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray());
    }

    public IReadOnlyList<string> KnownSecrets { get; }

    public IReadOnlyList<string> HomeDirectories { get; }

    public override string ToString() =>
        $"AgentTraceSanitizationContext {{ KnownSecretCount = {KnownSecrets.Count}, HomeDirectoryCount = {HomeDirectories.Count}, Values = [REDACTED] }}";
}

/// <summary>
/// Converts an untrusted/raw Agent trace into the stable persisted schema.
/// Unknown fields are dropped and high-risk payloads are replaced with typed
/// redaction markers before the result can be stored in workflow_tasks.
/// </summary>
public sealed partial class AgentTraceSanitizer
{
    private const string Redacted = "[REDACTED]";
    private const string ClipboardRedacted = "[REDACTED:clipboard]";
    private const string HttpBodyRedacted = "[REDACTED:http-body]";
    private const string FileContentRedacted = "[REDACTED:file-content]";
    private const string ScreenshotRedacted = "[REDACTED:screenshot]";

    private static readonly HashSet<string> SecretPropertyNames = new(
        StringComparer.Ordinal)
    {
        "authorization",
        "cookie",
        "setcookie",
        "apikey",
        "secret",
        "password",
        "credential",
        "accesstoken",
        "refreshtoken",
        "bearertoken",
    };

    private static readonly HashSet<string> HttpBodyPropertyNames = new(
        StringComparer.Ordinal)
    {
        "body",
        "httpbody",
        "requestbody",
        "responsebody",
        "rawrequest",
        "rawresponse",
    };

    private static readonly HashSet<string> FileContentPropertyNames = new(
        StringComparer.Ordinal)
    {
        "content",
        "filecontent",
        "rawcontent",
        "contentbytes",
        "filebytes",
    };

    public AgentTraceSanitizationResult Sanitize(
        JsonElement rawTrace,
        IReadOnlyCollection<string>? knownSecrets = null,
        IReadOnlyCollection<string>? homeDirectories = null)
    {
        if (rawTrace.ValueKind != JsonValueKind.Object)
        {
            throw new ArgumentException(
                "An Agent trace must be a JSON object.",
                nameof(rawTrace));
        }

        var sourceVersion = ReadSourceVersion(rawTrace);
        var source = JsonSerializer.Deserialize<AgentActionTrace>(
                rawTrace.GetRawText(),
                DomainJson.Options)
            ?? throw new JsonException("The Agent trace is empty.");
        var secrets = NormalizeValues(knownSecrets);
        var homes = NormalizeValues(homeDirectories);
        var safe = new AgentActionTrace(
            SanitizeText(source.ProviderId, secrets, homes)!,
            source.ExecutionMode,
            source.Status,
            SanitizeText(source.UserInstruction, secrets, homes)!,
            source.StartedAtUnixMs,
            AgentTraceSchema.CurrentVersion,
            SanitizeScreenContext(source.ScreenContext, secrets, homes),
            source.Events.Select(agentEvent => SanitizeEvent(
                agentEvent,
                secrets,
                homes)).ToArray(),
            SanitizeText(source.ResultSummary, secrets, homes),
            SanitizeText(source.Model, secrets, homes),
            source.TokenUsage,
            source.Artifacts.Select(artifact => SanitizeArtifact(
                artifact,
                secrets,
                homes)).ToArray(),
            source.CompletedAtUnixMs,
            SanitizeText(source.FailureReason, secrets, homes));
        return new AgentTraceSanitizationResult(
            safe,
            sourceVersion,
            AgentTraceSchema.Classify(sourceVersion));
    }

    private static int ReadSourceVersion(JsonElement rawTrace)
    {
        if (!rawTrace.TryGetProperty("schemaVersion", out var version))
        {
            return AgentTraceSchema.CurrentVersion;
        }
        if (version.ValueKind != JsonValueKind.Number
            || !version.TryGetInt32(out var value)
            || value < 0)
        {
            throw new JsonException("The Agent trace schema version is invalid.");
        }
        return value;
    }

    private static AgentScreenContextMetadata? SanitizeScreenContext(
        AgentScreenContextMetadata? context,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes) => context is null
        ? null
        : new AgentScreenContextMetadata(
            SanitizeText(context.AppName, secrets, homes),
            SanitizeText(context.ProcessName, secrets, homes),
            SanitizeText(context.WindowTitle, secrets, homes),
            context.Sources
                .Select(value => SanitizeText(value, secrets, homes)!)
                .ToArray(),
            context.Warnings
                .Select(value => SanitizeText(value, secrets, homes)!)
                .ToArray(),
            context.CapturedAtUnixMs);

    private static AgentActionEvent SanitizeEvent(
        AgentActionEvent agentEvent,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes) => new(
        SanitizeText(agentEvent.Id, secrets, homes)!,
        agentEvent.Kind,
        SanitizeText(agentEvent.Title, secrets, homes)!,
        SanitizeEventDetail(
            agentEvent.Detail,
            agentEvent.ToolName,
            secrets,
            homes),
        agentEvent.TimestampUnixMs,
        agentEvent.ElapsedMs,
        SanitizeText(agentEvent.ToolName, secrets, homes),
        agentEvent.IsFailure);

    private static AgentArtifact SanitizeArtifact(
        AgentArtifact artifact,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes) => new(
        SanitizeText(artifact.Id, secrets, homes)!,
        artifact.Kind,
        SanitizePath(artifact.Path, secrets, homes),
        SanitizeText(artifact.Summary, secrets, homes),
        artifact.UpdatedAtUnixMs);

    private static string? SanitizeEventDetail(
        string? detail,
        string? toolName,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes)
    {
        if (detail is null)
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(detail);
            return SanitizeJson(document.RootElement, secrets, homes);
        }
        catch (JsonException)
        {
            return NormalizeName(toolName ?? string.Empty) switch
            {
                "clipboard" or "clipboardread" or "clipboardwrite" =>
                    ClipboardRedacted,
                "httprequest" or "webfetch" => HttpBodyRedacted,
                "readfile" or "writefile" or "editfile" or "notebookedit" =>
                    FileContentRedacted,
                _ => SanitizeText(detail, secrets, homes),
            };
        }
    }

    private static string SanitizeJson(
        JsonElement element,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            WriteElement(writer, element, propertyName: null, secrets, homes);
        }
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    private static void WriteElement(
        Utf8JsonWriter writer,
        JsonElement element,
        string? propertyName,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes)
    {
        var category = RedactionCategory(propertyName);
        if (category is not null)
        {
            writer.WriteStringValue(category);
            return;
        }

        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var property in element.EnumerateObject())
                {
                    writer.WritePropertyName(property.Name);
                    WriteElement(writer, property.Value, property.Name, secrets, homes);
                }
                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var item in element.EnumerateArray())
                {
                    WriteElement(writer, item, propertyName: null, secrets, homes);
                }
                writer.WriteEndArray();
                break;
            case JsonValueKind.String:
                var value = element.GetString() ?? string.Empty;
                writer.WriteStringValue(IsPathProperty(propertyName)
                    ? SanitizePath(value, secrets, homes)
                    : SanitizeText(value, secrets, homes));
                break;
            case JsonValueKind.Number:
                element.WriteTo(writer);
                break;
            case JsonValueKind.True:
                writer.WriteBooleanValue(true);
                break;
            case JsonValueKind.False:
                writer.WriteBooleanValue(false);
                break;
            case JsonValueKind.Null:
                writer.WriteNullValue();
                break;
            default:
                writer.WriteNullValue();
                break;
        }
    }

    private static string? RedactionCategory(string? propertyName)
    {
        var normalized = NormalizeName(propertyName ?? string.Empty);
        if (SecretPropertyNames.Contains(normalized))
        {
            return Redacted;
        }
        if (normalized.Contains("clipboard", StringComparison.Ordinal))
        {
            return ClipboardRedacted;
        }
        if (HttpBodyPropertyNames.Contains(normalized))
        {
            return HttpBodyRedacted;
        }
        if (FileContentPropertyNames.Contains(normalized))
        {
            return FileContentRedacted;
        }
        if (normalized.Contains("screenshot", StringComparison.Ordinal)
            || normalized is "imagepath" or "imagebytes" or "rawimage")
        {
            return ScreenshotRedacted;
        }
        return null;
    }

    private static bool IsPathProperty(string? propertyName)
    {
        var normalized = NormalizeName(propertyName ?? string.Empty);
        return normalized is "path" or "filepath" or "directory" or "directorypath";
    }

    private static string SanitizePath(
        string path,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes)
    {
        var safe = SanitizeText(path, secrets, homes) ?? string.Empty;
        var normalized = safe.Replace('\\', '/');
        return normalized.Contains("/screenshots/", StringComparison.OrdinalIgnoreCase)
            || normalized.EndsWith("/screenshots", StringComparison.OrdinalIgnoreCase)
            ? ScreenshotRedacted
            : safe;
    }

    private static string? SanitizeText(
        string? value,
        IReadOnlyList<string> secrets,
        IReadOnlyList<string> homes)
    {
        if (value is null)
        {
            return null;
        }

        var safe = value;
        foreach (var secret in secrets.OrderByDescending(item => item.Length))
        {
            safe = safe.Replace(secret, Redacted, StringComparison.Ordinal);
        }
        foreach (var home in homes.OrderByDescending(item => item.Length))
        {
            safe = safe.Replace(
                home.TrimEnd('\\', '/'),
                "~",
                StringComparison.OrdinalIgnoreCase);
        }
        safe = AuthorizationPattern().Replace(safe, "Authorization: " + Redacted);
        safe = CookiePattern().Replace(safe, "Cookie: " + Redacted);
        safe = QuerySecretPattern().Replace(safe, "$1=" + Redacted);
        safe = WindowsHomePattern().Replace(safe, "~");
        safe = MacHomePattern().Replace(safe, "~");
        safe = LinuxHomePattern().Replace(safe, "~");
        return safe;
    }

    private static IReadOnlyList<string> NormalizeValues(
        IReadOnlyCollection<string>? values) => (values ?? [])
        .Where(value => !string.IsNullOrWhiteSpace(value))
        .Select(value => value.Trim())
        .Distinct(StringComparer.Ordinal)
        .ToArray();

    private static string NormalizeName(string value) => new(
        value.Where(char.IsLetterOrDigit)
            .Select(char.ToLowerInvariant)
            .ToArray());

    [GeneratedRegex(
        @"\bAuthorization\s*[:=]\s*(?:Bearer\s+)?[^\s,;\""}\]]+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex AuthorizationPattern();

    [GeneratedRegex(
        @"\b(?:Cookie|Set-Cookie)\s*[:=]\s*[^\r\n,;]+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CookiePattern();

    [GeneratedRegex(
        @"\b(api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password)=([^&\s]+)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex QuerySecretPattern();

    [GeneratedRegex(
        @"\b[A-Z]:[\\/]+Users[\\/]+[^\\/\s\""']+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex WindowsHomePattern();

    [GeneratedRegex(
        @"/Users/[^/\s\""']+",
        RegexOptions.CultureInvariant)]
    private static partial Regex MacHomePattern();

    [GeneratedRegex(
        @"/home/[^/\s\""']+",
        RegexOptions.CultureInvariant)]
    private static partial Regex LinuxHomePattern();
}
