using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentSidecarDtoTests
{
    [Fact]
    public void Run_request_serializes_explicit_schema_and_rust_camel_case_keys()
    {
        var request = new BuiltinAgentSidecarRunRequest(
            taskId: "task-1",
            instruction: "创建报告",
            provider: new BuiltinAgentSidecarProviderConfig(
                providerId: "provider-openai",
                baseUrl: "https://example.test/v1",
                model: "gpt-test",
                apiKey: "test-api-key",
                timeoutSeconds: 300),
            content: [new BuiltinAgentSidecarContentPart("trusted intent")],
            limits: new BuiltinAgentSidecarLoopLimits(),
            workspaceDirectory: Path.Combine(Path.GetTempPath(), "voxflow-agent-workspace"));

        var json = JsonSerializer.Serialize(request, DomainJson.Options);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        Assert.Equal(BuiltinAgentSidecarProtocol.CurrentSchemaVersion,
            root.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("task-1", root.GetProperty("taskId").GetString());
        Assert.True(root.TryGetProperty("workspaceDirectory", out var workspace));
        var workspacePath = workspace.GetString();
        Assert.NotNull(workspacePath);
        Assert.True(Path.IsPathFullyQualified(workspacePath));
        Assert.Equal("provider-openai",
            root.GetProperty("provider").GetProperty("providerId").GetString());
        Assert.Equal("text", root.GetProperty("content")[0].GetProperty("type").GetString());
        Assert.Equal(12, root.GetProperty("limits").GetProperty("maxSteps").GetInt32());
        Assert.DoesNotContain("test-api-key", request.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("test-api-key", request.Provider.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void Current_unversioned_event_is_treated_as_schema_one_for_macos_compatibility()
    {
        const string json = """
        {
          "event": "modelDelta",
          "text": "处理中",
          "futureField": "ignored"
        }
        """;

        var runtimeEvent = Assert.IsType<BuiltinAgentSidecarEvent>(
            JsonSerializer.Deserialize<BuiltinAgentSidecarEvent>(json, DomainJson.Options));
        var normalizedKnownJson = JsonSerializer.Serialize(runtimeEvent, DomainJson.Options);

        Assert.Equal(BuiltinAgentSidecarProtocol.CurrentSchemaVersion,
            runtimeEvent.SchemaVersion);
        Assert.Equal(SchemaCompatibility.Current, runtimeEvent.SchemaCompatibility);
        Assert.Equal("modelDelta", runtimeEvent.Event);
        Assert.Equal("处理中", runtimeEvent.Text);
        Assert.DoesNotContain("futureField", normalizedKnownJson, StringComparison.Ordinal);
    }

    [Fact]
    public void Newer_sidecar_schema_is_detected_without_deserializing_unknown_payload()
    {
        const string json = """
        {
          "schemaVersion": 23,
          "event": "turnCompleted",
          "summary": "done",
          "futureSecretPayload": "must-not-survive"
        }
        """;

        var runtimeEvent = Assert.IsType<BuiltinAgentSidecarEvent>(
            JsonSerializer.Deserialize<BuiltinAgentSidecarEvent>(json, DomainJson.Options));
        var normalizedKnownJson = JsonSerializer.Serialize(runtimeEvent, DomainJson.Options);

        Assert.Equal(23, runtimeEvent.SchemaVersion);
        Assert.Equal(SchemaCompatibility.Newer, runtimeEvent.SchemaCompatibility);
        Assert.Equal("done", runtimeEvent.Summary);
        Assert.DoesNotContain("must-not-survive", normalizedKnownJson, StringComparison.Ordinal);
    }

    [Fact]
    public void Tool_requested_event_round_trips_the_shared_tool_call_contract()
    {
        const string json = """
        {
          "schemaVersion": 1,
          "event": "toolRequested",
          "toolCall": {
            "id": "write-1",
            "name": "write_file",
            "arguments": { "file_path": "report.md", "content": "hello" }
          }
        }
        """;

        var runtimeEvent = Assert.IsType<BuiltinAgentSidecarEvent>(
            JsonSerializer.Deserialize<BuiltinAgentSidecarEvent>(json, DomainJson.Options));

        Assert.Equal("write_file", runtimeEvent.ToolCall?.Name);
        Assert.Equal(
            "report.md",
            runtimeEvent.ToolCall?.Arguments.GetProperty("file_path").GetString());
    }
}
