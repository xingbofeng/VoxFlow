using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class AgentContractTests
{
    [Fact]
    public void Agent_trace_round_trips_safe_macos_equivalent_fields()
    {
        var trace = new AgentActionTrace(
            providerId: "provider-openai",
            executionMode: AgentExecutionMode.BuiltinAgent,
            status: WorkflowTaskStatus.Completed,
            userInstruction: "帮我把选区改正式并写入文件",
            startedAtUnixMs: 1_720_000_000_000,
            screenContext: new AgentScreenContextMetadata(
                appName: "Word",
                processName: "WINWORD.EXE",
                windowTitle: "Plan.docx",
                sources: ["selectedText", "visibleText"],
                warnings: ["ocrSkipped"],
                capturedAtUnixMs: 1_720_000_000_010),
            events:
            [
                new AgentActionEvent(
                    id: "event-1",
                    kind: AgentActionEventKind.ToolResolved,
                    title: "工具完成",
                    detail: "created file",
                    timestampUnixMs: 1_720_000_000_100,
                    elapsedMs: 100,
                    toolName: "write_file",
                    isFailure: false),
            ],
            resultSummary: "已完成",
            model: "gpt-test",
            tokenUsage: new AgentTokenUsage(10, 2, 12),
            artifacts:
            [
                new AgentArtifact(
                    id: "artifact-1",
                    kind: AgentArtifactKind.File,
                    path: "report.md",
                    summary: "报告",
                    updatedAtUnixMs: 1_720_000_000_090),
            ],
            completedAtUnixMs: 1_720_000_000_200);

        var json = JsonSerializer.Serialize(trace, DomainJson.Options);
        var restored = Assert.IsType<AgentActionTrace>(
            JsonSerializer.Deserialize<AgentActionTrace>(json, DomainJson.Options));

        Assert.Equal(AgentTraceSchema.CurrentVersion, restored.SchemaVersion);
        Assert.Equal(SchemaCompatibility.Current, restored.SchemaCompatibility);
        Assert.Equal("provider-openai", restored.ProviderId);
        Assert.Equal(WorkflowTaskStatus.Completed, restored.Status);
        Assert.Equal("write_file", restored.Events.Single().ToolName);
        Assert.Equal(12, restored.TokenUsage?.TotalTokens);
        Assert.Equal("report.md", restored.Artifacts.Single().Path);
        Assert.Equal(["selectedText", "visibleText"], restored.ScreenContext?.Sources);
        Assert.DoesNotContain("screenshot", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Newer_trace_schema_ignores_unknown_fields_but_keeps_safe_basic_information()
    {
        const string json = """
        {
          "schemaVersion": 99,
          "providerId": "future-provider",
          "executionMode": "builtinAgent",
          "status": "completed",
          "userInstruction": "创建报告",
          "startedAtUnixMs": 1720000000000,
          "futurePayload": {
            "apiKey": "must-not-survive",
            "rawClipboard": "private"
          }
        }
        """;

        var trace = Assert.IsType<AgentActionTrace>(
            JsonSerializer.Deserialize<AgentActionTrace>(json, DomainJson.Options));
        var safeKnownJson = JsonSerializer.Serialize(trace, DomainJson.Options);

        Assert.Equal(99, trace.SchemaVersion);
        Assert.Equal(SchemaCompatibility.Newer, trace.SchemaCompatibility);
        Assert.Equal("future-provider", trace.ProviderId);
        Assert.Empty(trace.Events);
        Assert.Empty(trace.Artifacts);
        Assert.DoesNotContain("futurePayload", safeKnownJson, StringComparison.Ordinal);
        Assert.DoesNotContain("must-not-survive", safeKnownJson, StringComparison.Ordinal);
        Assert.DoesNotContain("private", safeKnownJson, StringComparison.Ordinal);
    }

    [Fact]
    public void Trace_missing_optional_fields_uses_current_compatible_defaults()
    {
        const string json = """
        {
          "providerId": "provider-openai",
          "executionMode": "builtinAgent",
          "status": "running",
          "userInstruction": "继续",
          "startedAtUnixMs": 1720000000000
        }
        """;

        var trace = Assert.IsType<AgentActionTrace>(
            JsonSerializer.Deserialize<AgentActionTrace>(json, DomainJson.Options));

        Assert.Equal(AgentTraceSchema.CurrentVersion, trace.SchemaVersion);
        Assert.Equal(SchemaCompatibility.Current, trace.SchemaCompatibility);
        Assert.Empty(trace.Events);
        Assert.Empty(trace.Artifacts);
        Assert.Null(trace.TokenUsage);
    }

    [Fact]
    public void Tool_call_and_result_round_trip_arbitrary_json_with_rust_keys()
    {
        using var argumentsDocument = JsonDocument.Parse(
            "{\"file_path\":\"report.md\",\"replace_all\":false}");
        using var resultDocument = JsonDocument.Parse(
            "{\"kind\":\"written\",\"bytes\":42}");
        var call = new AgentToolCall(
            "call-1",
            "write_file",
            argumentsDocument.RootElement);
        var result = AgentToolResult.Success(
            "write_file",
            resultDocument.RootElement);

        var callJson = JsonSerializer.Serialize(call, DomainJson.Options);
        var resultJson = JsonSerializer.Serialize(result, DomainJson.Options);
        var restoredCall = Assert.IsType<AgentToolCall>(
            JsonSerializer.Deserialize<AgentToolCall>(callJson, DomainJson.Options));
        var restoredResult = Assert.IsType<AgentToolResult>(
            JsonSerializer.Deserialize<AgentToolResult>(resultJson, DomainJson.Options));

        Assert.Equal("report.md", restoredCall.Arguments.GetProperty("file_path").GetString());
        Assert.Equal(42, restoredResult.Result?.GetProperty("bytes").GetInt32());
        Assert.Contains("\"toolName\":\"write_file\"", resultJson, StringComparison.Ordinal);
        Assert.DoesNotContain("tool_name", resultJson, StringComparison.Ordinal);
    }

    [Fact]
    public void Failed_tool_result_requires_structured_error_and_omits_result()
    {
        var result = AgentToolResult.Failure(
            "replace_selection",
            "missing_selection",
            "The original selection is unavailable.");

        var json = JsonSerializer.Serialize(result, DomainJson.Options);

        Assert.False(result.Ok);
        Assert.Equal("missing_selection", result.Error?.Code);
        Assert.DoesNotContain("\"result\"", json, StringComparison.Ordinal);
        Assert.Contains("\"error\"", json, StringComparison.Ordinal);
    }
}
