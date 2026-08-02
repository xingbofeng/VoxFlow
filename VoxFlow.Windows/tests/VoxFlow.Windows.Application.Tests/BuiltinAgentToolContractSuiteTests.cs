using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

/// <summary>
/// Cross-tool release contract.  Individual host tests exercise the concrete
/// policy, while this suite makes it impossible to add a sidecar-visible tool
/// without normal, rejected, cancellation, and trace-redaction evidence.
/// </summary>
public sealed class BuiltinAgentToolContractSuiteTests
{
    [Fact]
    public async Task Every_approved_tool_has_normal_rejected_cancelled_and_redacted_trace_evidence()
    {
        var evidence = ToolEvidence();
        Assert.Equal(17, evidence.Count);
        Assert.Equal(
            BuiltinAgentToolRegistry.ApprovedNames.OrderBy(name => name),
            evidence.Keys.OrderBy(name => name));

        var normalInvocations = new List<string>();
        var dispatcher = new BuiltinAgentToolDispatcher(evidence.Keys.ToDictionary(
            name => name,
            name => new Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>((call, cancellationToken) =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                normalInvocations.Add(call.Name);
                return Task.FromResult(AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
                {
                    outcome = "normal",
                })));
            }),
            StringComparer.Ordinal));

        foreach (var (toolName, arguments) in evidence)
        {
            // Normal: an approved, schema-valid call reaches its trusted host.
            var normal = await dispatcher.DispatchAsync(
                new AgentToolCall($"normal-{toolName}", toolName, arguments),
                CancellationToken.None);
            Assert.True(normal.Ok);
            Assert.Equal(toolName, normal.ToolName);

            // Rejected: the dispatcher never sends malformed calls to a host.
            var rejected = await dispatcher.DispatchAsync(
                new AgentToolCall($"rejected-{toolName}", toolName, Json("{\"unexpected\":true}")),
                CancellationToken.None);
            Assert.False(rejected.Ok);
            Assert.Equal("invalid_tool_arguments", rejected.Error?.Code);

            // Cancelled: the shared boundary propagates cancellation to every
            // host rather than converting it into a potentially misleading success.
            using var cancellation = new CancellationTokenSource();
            cancellation.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => dispatcher.DispatchAsync(
                new AgentToolCall($"cancelled-{toolName}", toolName, arguments),
                cancellation.Token));

            AssertTraceIsRedactedFor(toolName);
        }

        Assert.Equal(evidence.Keys.OrderBy(name => name), normalInvocations.OrderBy(name => name));
    }

    private static void AssertTraceIsRedactedFor(string toolName)
    {
        var rawSecret = $"tool-secret-{toolName}-1234567890";
        var rawTrace = new AgentActionTrace(
            providerId: "fixture-provider",
            executionMode: AgentExecutionMode.BuiltinAgent,
            status: WorkflowTaskStatus.Completed,
            userInstruction: "fixture instruction",
            startedAtUnixMs: 100,
            events:
            [
                new AgentActionEvent(
                    id: $"event-{toolName}",
                    kind: AgentActionEventKind.ToolResolved,
                    title: "Tool completed",
                    detail: JsonSerializer.Serialize(new
                    {
                        authorization = $"Bearer {rawSecret}",
                        body = rawSecret,
                        content = rawSecret,
                        clipboardText = rawSecret,
                        screenshotPath = @"C:\\Users\\Fixture\\AppData\\Local\\VoxFlow\\screenshots\\evidence.png",
                    }),
                    timestampUnixMs: 101,
                    elapsedMs: 1,
                    toolName,
                    isFailure: false),
            ]);
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(rawTrace, DomainJson.Options));

        var sanitized = new AgentTraceSanitizer().Sanitize(
            document.RootElement,
            knownSecrets: [rawSecret],
            homeDirectories: [@"C:\Users\Fixture"]);
        var persisted = JsonSerializer.Serialize(sanitized.Trace, DomainJson.Options);

        Assert.Equal(toolName, sanitized.Trace.Events.Single().ToolName);
        Assert.DoesNotContain(rawSecret, persisted, StringComparison.Ordinal);
        Assert.DoesNotContain("evidence.png", persisted, StringComparison.Ordinal);
        Assert.Contains("[REDACTED]", persisted, StringComparison.Ordinal);
    }

    private static IReadOnlyDictionary<string, JsonElement> ToolEvidence() =>
        new Dictionary<string, JsonElement>(StringComparer.Ordinal)
        {
            ["read_file"] = Json("{\"file_path\":\"README.md\"}"),
            ["search_transcriptions"] = Json("{\"query\":\"meeting\"}"),
            ["respond"] = Json("{\"mode\":\"final\",\"text\":\"done\"}"),
            ["ask_user_question"] = Json("{\"questions\":[]}"),
            ["write_file"] = Json("{\"file_path\":\"note.txt\",\"content\":\"body\"}"),
            ["edit_file"] = Json("{\"file_path\":\"note.txt\",\"old_string\":\"old\",\"new_string\":\"new\"}"),
            ["notebook_edit"] = Json("{\"notebook_path\":\"note.ipynb\",\"new_source\":\"print(1)\"}"),
            ["list_files"] = Json("{}"),
            ["glob_files"] = Json("{\"pattern\":\"*.cs\"}"),
            ["grep_files"] = Json("{\"pattern\":\"VoxFlow\"}"),
            ["clipboard"] = Json("{\"action\":\"read_text\"}"),
            ["keyboard"] = Json("{\"action\":\"type\",\"text\":\"hello\"}"),
            ["text_field"] = Json("{\"action\":\"read_selection\"}"),
            ["http_request"] = Json("{\"url\":\"https://example.test\"}"),
            ["open_url"] = Json("{\"url\":\"https://example.test\"}"),
            ["web_fetch"] = Json("{\"url\":\"https://example.test\",\"prompt\":\"summarize\"}"),
            ["web_search"] = Json("{\"query\":\"VoxFlow\"}"),
        };

    private static JsonElement Json(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }
}
