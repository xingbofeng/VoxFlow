using System.Globalization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Output;

public interface IUnicodeInputSender
{
    bool SendTextElement(string textElement);
}

public sealed record UnicodeKeyboardEvent(char CodeUnit, bool IsKeyUp);

public static class UnicodeKeyboardEventEncoder
{
    public static IReadOnlyList<UnicodeKeyboardEvent> Encode(string textElement)
    {
        ArgumentNullException.ThrowIfNull(textElement);
        var events = new UnicodeKeyboardEvent[textElement.Length * 2];
        for (var index = 0; index < textElement.Length; index++)
        {
            events[index * 2] = new UnicodeKeyboardEvent(
                textElement[index],
                IsKeyUp: false);
            events[(index * 2) + 1] = new UnicodeKeyboardEvent(
                textElement[index],
                IsKeyUp: true);
        }

        return events;
    }
}

public sealed class SimulatedTypingService
{
    private static readonly TimeSpan BatchInterval = TimeSpan.FromMilliseconds(2);

    private readonly IUnicodeInputSender unicodeInput;
    private readonly IQuickPasteOutput quickPaste;
    private readonly IOutputDelay delay;

    public SimulatedTypingService(
        IUnicodeInputSender unicodeInput,
        IQuickPasteOutput quickPaste,
        IOutputDelay? delay = null)
    {
        this.unicodeInput = unicodeInput
            ?? throw new ArgumentNullException(nameof(unicodeInput));
        this.quickPaste = quickPaste
            ?? throw new ArgumentNullException(nameof(quickPaste));
        this.delay = delay ?? new SystemTypingDelay();
    }

    public async ValueTask<OutputResult> TypeAsync(
        string text,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        cancellationToken.ThrowIfCancellationRequested();

        if (text.Contains('\r', StringComparison.Ordinal)
            || text.Contains('\n', StringComparison.Ordinal))
        {
            return await quickPaste.PasteAsync(text, cancellationToken)
                .ConfigureAwait(false);
        }

        var starts = StringInfo.ParseCombiningCharacters(text);
        for (var index = 0; index < starts.Length; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var end = index + 1 < starts.Length ? starts[index + 1] : text.Length;
            var textElement = text[starts[index]..end];
            if (!unicodeInput.SendTextElement(textElement))
            {
                return new OutputResult(
                    OutputResultKind.InjectionFailed,
                    VoxFlowErrorCode.InputInjectionFailure);
            }

            if (index + 1 < starts.Length)
            {
                await delay.DelayAsync(BatchInterval, cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        return new OutputResult(OutputResultKind.Inserted);
    }

    private sealed class SystemTypingDelay : IOutputDelay
    {
        public ValueTask DelayAsync(
            TimeSpan delay,
            CancellationToken cancellationToken) =>
            new(Task.Delay(delay, cancellationToken));
    }
}

public sealed class WindowsUnicodeInputSender : IUnicodeInputSender
{
    public bool SendTextElement(string textElement)
    {
        ArgumentNullException.ThrowIfNull(textElement);
        var encoded = UnicodeKeyboardEventEncoder.Encode(textElement);
        if (encoded.Count == 0)
        {
            return true;
        }

        var inputs = new WindowsInputInterop.NativeInput[encoded.Count];
        for (var index = 0; index < encoded.Count; index++)
        {
            var item = encoded[index];
            inputs[index] = WindowsInputInterop.CreateUnicode(
                item.CodeUnit,
                item.IsKeyUp);
        }

        return WindowsInputInterop.SendAll(inputs);
    }
}
