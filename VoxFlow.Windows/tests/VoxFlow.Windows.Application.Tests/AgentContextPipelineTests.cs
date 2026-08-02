using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentContextPipelineTests
{
    [Fact]
    public async Task Selection_is_returned_as_untrusted_context_for_the_frozen_target()
    {
        var target = Target();
        var pipeline = new AgentContextPipeline(new FakeReader(new(
            Selection(target, "screen text"),
            "draft input",
            "visible page text")));

        var result = await pipeline.CaptureAsync(target, CancellationToken.None);

        Assert.Equal("screen text", result.SelectedText);
        Assert.Equal("draft input", result.FocusedInputText);
        Assert.Equal("visible page text", result.VisibleText);
        Assert.Empty(result.Warnings);
        Assert.Equal(AgentContextSnapshot.UntrustedContextLabel, "untrusted_context");
    }

    [Fact]
    public async Task Reader_failure_degrades_to_a_safe_warning()
    {
        var result = await new AgentContextPipeline(new ThrowingReader())
            .CaptureAsync(Target(), CancellationToken.None);

        Assert.Null(result.SelectedText);
        Assert.Equal(["context_unavailable"], result.Warnings);
    }

    [Fact]
    public async Task Secure_context_is_skipped_without_returning_any_desktop_text()
    {
        var result = await new AgentContextPipeline(new FakeReader(new(
            Selection(Target(), "must not escape"),
            "secret input",
            "secret visible",
            IsSecure: true))).CaptureAsync(Target(), CancellationToken.None);

        Assert.Null(result.SelectedText);
        Assert.Null(result.FocusedInputText);
        Assert.Null(result.VisibleText);
        Assert.Equal(["context_secure"], result.Warnings);
    }

    [Fact]
    public async Task Reader_timeout_degrades_without_blocking_the_voice_instruction()
    {
        var result = await new AgentContextPipeline(
            new BlockingReader(), TimeSpan.FromMilliseconds(5))
            .CaptureAsync(Target(), CancellationToken.None);

        Assert.Null(result.SelectedText);
        Assert.Equal(["context_timeout"], result.Warnings);
    }

    [Fact]
    public async Task Sufficient_uia_text_does_not_start_visual_ocr_fallback()
    {
        var visual = new CapturingVisualFallback();
        var pipeline = new AgentContextPipeline(new FakeReader(new(
            Selection(Target(), new string('s', AgentContextPipeline.MinimumStructuredTextCharacters)),
            null,
            null)), visual);

        var result = await pipeline.CaptureAsync(Target(), "C:\\task", CancellationToken.None);

        Assert.False(visual.Read);
        Assert.Null(result.OcrText);
    }

    [Fact]
    public async Task Insufficient_uia_text_uses_untrusted_ocr_text_and_keeps_only_a_safe_warning()
    {
        var visual = new CapturingVisualFallback(new("OCR fallback text", "visual_fallback"));
        var pipeline = new AgentContextPipeline(new FakeReader(new(null, null, "short")), visual);

        var result = await pipeline.CaptureAsync(Target(), "C:\\task", CancellationToken.None);

        Assert.True(visual.Read);
        Assert.Equal("C:\\task", visual.Workspace);
        Assert.Equal("OCR fallback text", result.OcrText);
        Assert.Equal(["visual_fallback"], result.Warnings);
    }

    private static ForegroundTargetSnapshot Target() => new(1, 2, "notepad", "Draft", new WindowBounds(0, 0, 100, 100), ProcessIntegrityLevel.Medium, [1], 1);
    private static SelectionSnapshot Selection(ForegroundTargetSnapshot target, string text) => new(text, SelectionAcquisitionSource.ShortcutCopy, target, [], [], SelectionEditability.ReadOnly, false, 1);
    private sealed class FakeReader(AgentContextReadResult result) : IAgentContextReader
    {
        public Task<AgentContextReadResult> ReadAsync(
            ForegroundTargetSnapshot target,
            CancellationToken cancellationToken) => Task.FromResult(result);
    }

    private sealed class ThrowingReader : IAgentContextReader
    {
        public Task<AgentContextReadResult> ReadAsync(ForegroundTargetSnapshot target, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("UIA body must not reach the task warning.");
    }

    private sealed class BlockingReader : IAgentContextReader
    {
        public async Task<AgentContextReadResult> ReadAsync(
            ForegroundTargetSnapshot target,
            CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return new AgentContextReadResult(null, null, null);
        }
    }

    private sealed class CapturingVisualFallback(AgentVisualTextFallbackResult? result = null)
        : IAgentVisualTextFallback
    {
        public bool Read { get; private set; }

        public string? Workspace { get; private set; }

        public Task<AgentVisualTextFallbackResult> ReadAsync(
            ForegroundTargetSnapshot target,
            string taskWorkspace,
            CancellationToken cancellationToken)
        {
            Read = true;
            Workspace = taskWorkspace;
            return Task.FromResult(result ?? new AgentVisualTextFallbackResult(null, null));
        }
    }
}
