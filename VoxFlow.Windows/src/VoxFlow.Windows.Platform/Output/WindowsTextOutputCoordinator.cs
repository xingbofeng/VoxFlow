using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Output;

public interface ITextOutputInjector
{
    ValueTask<OutputResult> InjectAsync(
        string text,
        CancellationToken cancellationToken);
}

public interface IOutputClipboardCopier
{
    bool TryCopy(string text);
}

public sealed class WindowsTextOutputCoordinator : IDictationOutput, IDictationTargetCapture
{
    private readonly object syncRoot = new();
    private readonly ITextOutputInjector injector;
    private readonly IOutputClipboardCopier clipboard;
    private readonly ForegroundTargetOutputGuard? targetGuard;
    private ForegroundTargetIdentity? originalTarget;
    private bool targetCaptureAttempted;

    public WindowsTextOutputCoordinator(
        ITextOutputInjector injector,
        IOutputClipboardCopier clipboard,
        ForegroundTargetOutputGuard? targetGuard = null)
    {
        this.injector = injector ?? throw new ArgumentNullException(nameof(injector));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.targetGuard = targetGuard;
    }

    public void CaptureOriginalTarget()
    {
        ForegroundTargetIdentity? captured;
        try
        {
            captured = targetGuard?.CaptureOriginal();
        }
        catch
        {
            captured = null;
        }

        lock (syncRoot)
        {
            originalTarget = captured;
            targetCaptureAttempted = true;
        }
    }

    public async ValueTask<OutputResult> WriteAsync(
        string text,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (cancellationToken.IsCancellationRequested)
        {
            return new OutputResult(OutputResultKind.Cancelled);
        }

        var decision = DecideTarget();
        if (decision is { Action: TargetAwareOutputAction.Copy })
        {
            if (cancellationToken.IsCancellationRequested)
            {
                return new OutputResult(OutputResultKind.Cancelled);
            }

            return CopyOrFailure(text, decision.Result!);
        }

        var result = await injector.InjectAsync(text, cancellationToken)
            .ConfigureAwait(false);
        if (result.Kind is not (
            OutputResultKind.PermissionDenied or
            OutputResultKind.InjectionFailed))
        {
            return result;
        }

        if (cancellationToken.IsCancellationRequested)
        {
            return new OutputResult(OutputResultKind.Cancelled);
        }

        return CopyOrFailure(text, result);
    }

    private TargetAwareOutputDecision? DecideTarget()
    {
        if (targetGuard is null)
        {
            return null;
        }

        ForegroundTargetIdentity? captured;
        bool attempted;
        lock (syncRoot)
        {
            captured = originalTarget;
            attempted = targetCaptureAttempted;
            originalTarget = null;
            targetCaptureAttempted = false;
        }

        return attempted
            ? targetGuard.DecideBeforeOutput(captured)
            : null;
    }

    private OutputResult CopyOrFailure(string text, OutputResult successResult) =>
        clipboard.TryCopy(text)
            ? successResult
            : new OutputResult(
                OutputResultKind.CopyFailed,
                VoxFlowErrorCode.ClipboardFailure);
}

public sealed class WindowsOutputClipboardCopier(
    IClipboardGateway clipboard) : IOutputClipboardCopier
{
    public bool TryCopy(string text)
    {
        try
        {
            _ = clipboard.WriteUnicodeText(text);
            return true;
        }
        catch (ClipboardOperationException)
        {
            return false;
        }
    }
}

public sealed class QuickPasteOutputInjector(
    IQuickPasteOutput quickPaste) : ITextOutputInjector
{
    public ValueTask<OutputResult> InjectAsync(
        string text,
        CancellationToken cancellationToken) =>
        quickPaste.PasteAsync(text, cancellationToken);
}

public sealed class SimulatedTypingOutputInjector(
    SimulatedTypingService simulatedTyping) : ITextOutputInjector
{
    public ValueTask<OutputResult> InjectAsync(
        string text,
        CancellationToken cancellationToken) =>
        simulatedTyping.TypeAsync(text, cancellationToken);
}

/// <summary>
/// Resolves the configured output mode for every completed dictation. Settings
/// can therefore change while the desktop runtime is alive without rebuilding
/// the microphone/ASR pipeline.
/// </summary>
public sealed class SettingsAwareTextOutputInjector : ITextOutputInjector
{
    private readonly Func<string> outputModeProvider;
    private readonly ITextOutputInjector quickPaste;
    private readonly ITextOutputInjector simulatedTyping;

    public SettingsAwareTextOutputInjector(
        Func<string> outputModeProvider,
        ITextOutputInjector quickPaste,
        ITextOutputInjector simulatedTyping)
    {
        this.outputModeProvider = outputModeProvider
            ?? throw new ArgumentNullException(nameof(outputModeProvider));
        this.quickPaste = quickPaste
            ?? throw new ArgumentNullException(nameof(quickPaste));
        this.simulatedTyping = simulatedTyping
            ?? throw new ArgumentNullException(nameof(simulatedTyping));
    }

    public ValueTask<OutputResult> InjectAsync(
        string text,
        CancellationToken cancellationToken) =>
        string.Equals(
            outputModeProvider(),
            "simulatedTyping",
            StringComparison.Ordinal)
            ? simulatedTyping.InjectAsync(text, cancellationToken)
            : quickPaste.InjectAsync(text, cancellationToken);
}
