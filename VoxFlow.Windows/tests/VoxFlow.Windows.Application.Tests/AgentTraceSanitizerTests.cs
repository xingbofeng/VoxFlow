using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentTraceSanitizerTests
{
    [Fact]
    public void Secrets_headers_clipboard_http_file_content_screenshot_and_home_are_sanitized()
    {
        using var document = JsonDocument.Parse("""
        {
          "schemaVersion": 1,
          "providerId": "fixture-provider",
          "executionMode": "builtinAgent",
          "status": "completed",
          "userInstruction": "Use sk-fixture-secret without exposing it",
          "startedAtUnixMs": 100,
          "events": [
            {
              "id": "event-1",
              "kind": "toolResolved",
              "title": "HTTP request completed",
              "detail": "{\"authorization\":\"Bearer auth-secret\",\"cookie\":\"session=cookie-secret\",\"clipboardText\":\"clipboard-private\",\"requestBody\":\"http-private\",\"fileContent\":\"file-private\",\"screenshotPath\":\"C:\\\\Users\\\\Alice\\\\AppData\\\\Local\\\\VoxFlow\\\\screenshots\\\\shot.png\",\"path\":\"C:\\\\Users\\\\Alice\\\\Documents\\\\report.md\",\"bytes\":42}",
              "timestampUnixMs": 120,
              "elapsedMs": null,
              "toolName": "http_request",
              "isFailure": false
            }
          ],
          "artifacts": [
            {
              "id": "artifact-1",
              "kind": "file",
              "path": "C:\\Users\\Alice\\Documents\\report.md",
              "summary": "saved with Authorization: Bearer summary-secret",
              "updatedAtUnixMs": 130
            }
          ],
          "futurePayload": {
            "apiKey": "unknown-secret",
            "rawClipboard": "unknown-private"
          }
        }
        """);
        var sanitizer = new AgentTraceSanitizer();

        var result = sanitizer.Sanitize(
            document.RootElement,
            knownSecrets: ["sk-fixture-secret"],
            homeDirectories: [@"C:\Users\Alice"]);
        var json = JsonSerializer.Serialize(result.Trace, DomainJson.Options);

        foreach (var forbidden in new[]
        {
            "sk-fixture-secret",
            "auth-secret",
            "cookie-secret",
            "clipboard-private",
            "http-private",
            "file-private",
            "summary-secret",
            "unknown-secret",
            "unknown-private",
            @"C:\Users\Alice",
            "shot.png",
        })
        {
            Assert.DoesNotContain(forbidden, json, StringComparison.OrdinalIgnoreCase);
        }

        Assert.Equal(AgentTraceSchema.CurrentVersion, result.Trace.SchemaVersion);
        Assert.Equal("~\\Documents\\report.md", result.Trace.Artifacts.Single().Path);
        using var safeDetail = JsonDocument.Parse(result.Trace.Events.Single().Detail!);
        Assert.Equal("[REDACTED]", safeDetail.RootElement.GetProperty("authorization").GetString());
        Assert.Equal("[REDACTED]", safeDetail.RootElement.GetProperty("cookie").GetString());
        Assert.Equal("[REDACTED:clipboard]", safeDetail.RootElement.GetProperty("clipboardText").GetString());
        Assert.Equal("[REDACTED:http-body]", safeDetail.RootElement.GetProperty("requestBody").GetString());
        Assert.Equal("[REDACTED:file-content]", safeDetail.RootElement.GetProperty("fileContent").GetString());
        Assert.Equal("[REDACTED:screenshot]", safeDetail.RootElement.GetProperty("screenshotPath").GetString());
        Assert.Equal("~\\Documents\\report.md", safeDetail.RootElement.GetProperty("path").GetString());
        Assert.Equal(42, safeDetail.RootElement.GetProperty("bytes").GetInt32());
    }

    [Theory]
    [InlineData("clipboard", "private clipboard text", "[REDACTED:clipboard]")]
    [InlineData("http_request", "private HTTP response body", "[REDACTED:http-body]")]
    [InlineData("read_file", "private file contents", "[REDACTED:file-content]")]
    public void Plain_high_risk_tool_detail_is_replaced_but_tool_identity_survives(
        string toolName,
        string unsafeDetail,
        string expectedDetail)
    {
        var trace = Trace(
            schemaVersion: AgentTraceSchema.CurrentVersion,
            events:
            [
                new AgentActionEvent(
                    "event-1",
                    AgentActionEventKind.ToolResolved,
                    "Tool completed",
                    unsafeDetail,
                    101,
                    elapsedMs: 1,
                    toolName,
                    isFailure: false),
            ]);
        using var raw = JsonDocument.Parse(
            JsonSerializer.Serialize(trace, DomainJson.Options));

        var result = new AgentTraceSanitizer().Sanitize(raw.RootElement);

        Assert.Equal(toolName, result.Trace.Events.Single().ToolName);
        Assert.Equal(expectedDetail, result.Trace.Events.Single().Detail);
    }

    [Theory]
    [InlineData(0, SchemaCompatibility.Legacy)]
    [InlineData(99, SchemaCompatibility.Newer)]
    public void Legacy_and_newer_documents_are_read_as_known_fields_and_normalized_to_current(
        int sourceVersion,
        SchemaCompatibility expectedCompatibility)
    {
        var trace = Trace(sourceVersion);
        var rawJson = JsonSerializer.Serialize(trace, DomainJson.Options)
            .TrimEnd('}') + ",\"unknown\":{\"secret\":\"drop-me\"}}";
        using var raw = JsonDocument.Parse(rawJson);

        var result = new AgentTraceSanitizer().Sanitize(raw.RootElement);
        var safeJson = JsonSerializer.Serialize(result.Trace, DomainJson.Options);

        Assert.Equal(sourceVersion, result.SourceSchemaVersion);
        Assert.Equal(expectedCompatibility, result.SourceCompatibility);
        Assert.Equal(AgentTraceSchema.CurrentVersion, result.Trace.SchemaVersion);
        Assert.Equal("fixture-provider", result.Trace.ProviderId);
        Assert.DoesNotContain("unknown", safeJson, StringComparison.Ordinal);
        Assert.DoesNotContain("drop-me", safeJson, StringComparison.Ordinal);
    }

    private static AgentActionTrace Trace(
        int schemaVersion,
        IReadOnlyList<AgentActionEvent>? events = null) => new(
        providerId: "fixture-provider",
        executionMode: AgentExecutionMode.BuiltinAgent,
        status: WorkflowTaskStatus.Completed,
        userInstruction: "fixture instruction",
        startedAtUnixMs: 100,
        schemaVersion,
        events: events,
        resultSummary: "done",
        model: "fixture-model",
        completedAtUnixMs: 200);
}
