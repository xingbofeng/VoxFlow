using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentOpenUrlToolHostTests
{
    [Fact]
    public async Task Explicit_voice_url_and_open_verb_can_open_the_default_browser()
    {
        var launcher = new FakeLauncher();
        var result = await Host("打开 https://example.com/docs", launcher).ExecuteAsync(
            Call("https://example.com/docs"), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal(new Uri("https://example.com/docs"), launcher.Opened);
        Assert.Equal("open_url", result.Result!.Value.GetProperty("action").GetString());
    }

    [Fact]
    public async Task Context_only_url_or_missing_open_verb_never_launches()
    {
        var launcher = new FakeLauncher();
        var host = new BuiltinAgentOpenUrlToolHost(
            new AgentToolAuthorizationPolicy("总结这个页面 https://example.com/docs"), launcher);

        var result = await host.ExecuteAsync(Call("https://example.com/docs"), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("user_intent_required", result.Error?.Code);
        Assert.Null(launcher.Opened);
    }

    [Theory]
    [InlineData("file:///C:/secret.txt")]
    [InlineData("data:text/plain,hello")]
    [InlineData("mailto:person@example.com")]
    public async Task Non_web_schemes_are_rejected(string url)
    {
        var result = await Host("打开 " + url).ExecuteAsync(Call(url), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("invalid_url", result.Error?.Code);
    }

    [Fact]
    public async Task Browser_failure_is_honest_and_not_a_successful_side_effect()
    {
        var launcher = new FakeLauncher(open: false);
        var host = new BuiltinAgentOpenUrlToolHost(
            new AgentToolAuthorizationPolicy("打开 https://example.com"), launcher);

        var result = await host.ExecuteAsync(Call("https://example.com"), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("open_url_failed", result.Error?.Code);
    }

    private static BuiltinAgentOpenUrlToolHost Host(
        string instruction,
        IAgentUrlLauncher? launcher = null) => new(
        new AgentToolAuthorizationPolicy(instruction), launcher ?? new FakeLauncher());

    private static AgentToolCall Call(string url) => new(
        "call-1", "open_url", JsonSerializer.SerializeToElement(new { url }));

    private sealed class FakeLauncher(bool open = true) : IAgentUrlLauncher
    {
        public Uri? Opened { get; private set; }

        public bool TryOpen(Uri uri)
        {
            if (open)
            {
                Opened = uri;
            }
            return open;
        }
    }
}
