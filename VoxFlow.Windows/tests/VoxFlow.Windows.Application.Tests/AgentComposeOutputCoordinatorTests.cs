using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentComposeOutputCoordinatorTests
{
    [Fact]
    public void Read_only_answer_is_copied_and_never_presented_as_a_side_effect()
    {
        var clipboard = new Clipboard(true);
        var summary = new Summary();
        var result = new AgentComposeOutputCoordinator(clipboard, summary)
            .Complete("answer", [AgentToolResult.Success("read_file")]);

        Assert.Equal(AgentComposeOutputStatus.Copied, result.Status);
        Assert.Equal("answer", clipboard.Text);
        Assert.Null(summary.Text);
    }

    [Fact]
    public void Successful_copy_notifies_an_optional_status_presenter()
    {
        var summary = new StatusSummary();

        var result = new AgentComposeOutputCoordinator(new Clipboard(true), summary)
            .Complete("answer", []);

        Assert.Equal(AgentComposeOutputStatus.Copied, result.Status);
        Assert.True(summary.Copied);
    }

    [Fact]
    public void Text_field_and_file_side_effects_show_summary_without_copy_or_submit()
    {
        var clipboard = new Clipboard(true);
        var summary = new Summary();
        var result = new AgentComposeOutputCoordinator(clipboard, summary).Complete(
            "Created the file and filled the field.",
            [
                AgentToolResult.Success("write_file"),
                AgentToolResult.Success("text_field", JsonSerializer.SerializeToElement(new { action = "insert" })),
            ]);

        Assert.Equal(AgentComposeOutputStatus.Summarized, result.Status);
        Assert.Equal("Created the file and filled the field.", summary.Text);
        Assert.Null(clipboard.Text);
    }

    [Fact]
    public void Copy_failure_and_partial_side_effect_cancellation_remain_honest()
    {
        var failedCopy = new AgentComposeOutputCoordinator(new Clipboard(false), new Summary())
            .Complete("answer", []);
        var summary = new Summary();
        var partialEffect = new AgentComposeOutputCoordinator(new Clipboard(true), summary)
            .Complete(null, [AgentToolResult.Success("write_file")]);

        Assert.Equal(AgentComposeOutputStatus.CopyFailed, failedCopy.Status);
        Assert.Equal("clipboard_copy_failed", failedCopy.SafeErrorCode);
        Assert.Equal(AgentComposeOutputStatus.Summarized, partialEffect.Status);
        Assert.Null(summary.Text);
    }

    private sealed class Clipboard(bool succeeds) : IAgentOutputClipboard
    {
        public string? Text { get; private set; }
        public bool TryCopy(string text)
        {
            if (!succeeds) return false;
            Text = text;
            return true;
        }
    }
    private sealed class Summary : IAgentOutputSummaryPresenter
    {
        public string? Text { get; private set; }
        public void ShowSummary(string? text) => Text = text;
    }

    private sealed class StatusSummary : IAgentOutputSummaryPresenter, IAgentOutputStatusPresenter
    {
        public bool Copied { get; private set; }

        public void ShowSummary(string? text) { }

        public void ShowCopied() => Copied = true;
    }
}
