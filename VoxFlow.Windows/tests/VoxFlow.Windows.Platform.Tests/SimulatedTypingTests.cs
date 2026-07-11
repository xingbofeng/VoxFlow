using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class SimulatedTypingTests
{
    [Theory]
    [InlineData("中文")]
    [InlineData("👩‍💻")]
    [InlineData("e\u0301")]
    public void Unicode_keyboard_events_preserve_every_utf16_code_unit(string textElement)
    {
        var events = UnicodeKeyboardEventEncoder.Encode(textElement);

        Assert.Equal(textElement.Length * 2, events.Count);
        for (var index = 0; index < textElement.Length; index++)
        {
            Assert.Equal(textElement[index], events[index * 2].CodeUnit);
            Assert.False(events[index * 2].IsKeyUp);
            Assert.Equal(textElement[index], events[(index * 2) + 1].CodeUnit);
            Assert.True(events[(index * 2) + 1].IsKeyUp);
        }
    }

    [Fact]
    public async Task Typing_batches_by_unicode_grapheme_cluster_with_two_millisecond_intervals()
    {
        var input = new CapturingUnicodeInputSender();
        var delay = new CapturingTypingDelay();
        var quickPaste = new CapturingQuickPasteOutput();
        var service = new SimulatedTypingService(input, quickPaste, delay);

        var result = await service.TypeAsync("A你👩‍💻e\u0301", CancellationToken.None);

        Assert.Equal(OutputResultKind.Inserted, result.Kind);
        Assert.Equal(["A", "你", "👩‍💻", "e\u0301"], input.TextElements);
        Assert.Equal(
            [
                TimeSpan.FromMilliseconds(2),
                TimeSpan.FromMilliseconds(2),
                TimeSpan.FromMilliseconds(2),
            ],
            delay.Delays);
        Assert.Null(quickPaste.Text);
    }

    [Fact]
    public async Task Cancellation_between_batches_stops_before_the_next_text_element()
    {
        using var cancellation = new CancellationTokenSource();
        var input = new CapturingUnicodeInputSender();
        var delay = new CapturingTypingDelay(() => cancellation.Cancel());
        var service = new SimulatedTypingService(
            input,
            new CapturingQuickPasteOutput(),
            delay);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await service.TypeAsync("AB", cancellation.Token));

        Assert.Equal(["A"], input.TextElements);
        Assert.Single(delay.Delays);
    }

    [Theory]
    [InlineData("first\nsecond")]
    [InlineData("first\r\nsecond")]
    public async Task Any_newline_falls_back_to_quick_paste_without_sending_enter(string text)
    {
        var input = new CapturingUnicodeInputSender();
        var quickPaste = new CapturingQuickPasteOutput();
        var service = new SimulatedTypingService(
            input,
            quickPaste,
            new CapturingTypingDelay());

        var result = await service.TypeAsync(text, CancellationToken.None);

        Assert.Equal(OutputResultKind.Inserted, result.Kind);
        Assert.Equal(text, quickPaste.Text);
        Assert.Empty(input.TextElements);
    }

    [Fact]
    public async Task Native_send_failure_is_classified_and_stops_remaining_clusters()
    {
        var input = new CapturingUnicodeInputSender(failAtCall: 2);
        var service = new SimulatedTypingService(
            input,
            new CapturingQuickPasteOutput(),
            new CapturingTypingDelay());

        var result = await service.TypeAsync("ABC", CancellationToken.None);

        Assert.Equal(OutputResultKind.InjectionFailed, result.Kind);
        Assert.Equal(VoxFlowErrorCode.InputInjectionFailure, result.ErrorCode);
        Assert.Equal(["A", "B"], input.TextElements);
    }

    private sealed class CapturingUnicodeInputSender(
        int failAtCall = int.MaxValue) : IUnicodeInputSender
    {
        public List<string> TextElements { get; } = [];

        public bool SendTextElement(string textElement)
        {
            TextElements.Add(textElement);
            return TextElements.Count != failAtCall;
        }
    }

    private sealed class CapturingTypingDelay(
        Action? afterDelay = null) : IOutputDelay
    {
        public List<TimeSpan> Delays { get; } = [];

        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Delays.Add(delay);
            afterDelay?.Invoke();
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.CompletedTask;
        }
    }

    private sealed class CapturingQuickPasteOutput : IQuickPasteOutput
    {
        public string? Text { get; private set; }

        public ValueTask<OutputResult> PasteAsync(
            string text,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Text = text;
            return ValueTask.FromResult(new OutputResult(OutputResultKind.Inserted));
        }
    }
}
