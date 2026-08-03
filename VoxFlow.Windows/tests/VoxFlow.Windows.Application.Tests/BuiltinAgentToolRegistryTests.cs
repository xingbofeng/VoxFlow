using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentToolRegistryTests
{
    [Fact]
    public void Exposes_the_exact_rust_sidecar_seventeen_tool_schema_golden()
    {
        var expected = new Dictionary<string, ToolGolden>(StringComparer.Ordinal)
        {
            ["read_file"] = new(["file_path"], ["file_path", "offset", "char_offset", "limit"]),
            ["search_transcriptions"] = new(["query"], ["query", "date_from", "date_to", "limit"]),
            ["respond"] = new(["mode", "text"], ["mode", "text", "severity"]),
            ["ask_user_question"] = new(["questions"], ["questions", "answers", "annotations", "metadata"]),
            ["write_file"] = new(["file_path", "content"], ["file_path", "content"]),
            ["edit_file"] = new(["file_path", "old_string", "new_string"], ["file_path", "old_string", "new_string", "replace_all"]),
            ["notebook_edit"] = new(["notebook_path", "new_source"], ["notebook_path", "cell_id", "new_source", "cell_type", "edit_mode"]),
            ["list_files"] = new([], ["path"]),
            ["glob_files"] = new(["pattern"], ["pattern", "path", "limit"]),
            ["grep_files"] = new(["pattern"], ["pattern", "path", "glob", "output_mode", "-B", "-A", "-C", "context", "-n", "-i", "type", "head_limit", "offset", "multiline"]),
            ["clipboard"] = new(["action"], ["action", "text", "image", "path"]),
            ["keyboard"] = new(["action"], ["action", "text", "key", "keys"]),
            ["text_field"] = new(["action"], ["action", "text"]),
            ["http_request"] = new(["url"], ["url", "method", "headers", "body"]),
            ["open_url"] = new(["url"], ["url"]),
            ["web_fetch"] = new(["url", "prompt"], ["url", "prompt"]),
            ["web_search"] = new(["query"], ["query", "allowed_domains", "blocked_domains", "num_results", "livecrawl", "search_type", "context_max_characters"]),
        };

        Assert.Equal(expected.Keys.OrderBy(name => name),
            BuiltinAgentToolRegistry.ApprovedNames.OrderBy(name => name));
        Assert.Equal(17, BuiltinAgentToolRegistry.ApprovedNames.Count);
        foreach (var (name, golden) in expected)
        {
            Assert.True(BuiltinAgentToolRegistry.TryGetSchema(name, out var schema));
            Assert.NotNull(schema);
            Assert.Equal(golden.ParameterNames.OrderBy(value => value), schema.Parameters.Keys.OrderBy(value => value));
            Assert.Equal(golden.RequiredNames.OrderBy(value => value), schema.RequiredParameters.OrderBy(value => value));
        }

        Assert.False(BuiltinAgentToolRegistry.IsApproved("shell"));
        Assert.False(BuiltinAgentToolRegistry.IsApproved("delete_file"));
        Assert.False(BuiltinAgentToolRegistry.IsApproved("agent_dispatch"));
    }

    [Theory]
    [InlineData("write_file", "{}")]
    [InlineData("web_search", "{\"query\": 3}")]
    [InlineData("open_url", "{\"url\": \"https://example.test\", \"extra\": true}")]
    public async Task Dispatcher_rejects_malformed_schema_calls_before_invoking_host(
        string toolName,
        string arguments)
    {
        var invoked = false;
        var dispatcher = new BuiltinAgentToolDispatcher(
            new Dictionary<string, Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>>
            {
                [toolName] = (_, _) =>
                {
                    invoked = true;
                    return Task.FromResult(AgentToolResult.Success(toolName));
                },
            });

        var result = await dispatcher.DispatchAsync(
            new AgentToolCall("call-1", toolName, JsonSerializer.Deserialize<JsonElement>(arguments)),
            CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("invalid_tool_arguments", result.Error?.Code);
        Assert.False(invoked);
    }

    private sealed record ToolGolden(
        IReadOnlyList<string> RequiredNames,
        IReadOnlyList<string> ParameterNames);
}
