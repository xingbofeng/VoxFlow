using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Dictation;

/// <summary>
/// An immutable, internally constructed view of the dictation lifecycle.
/// Keeping construction private prevents consumers from publishing phase/data
/// combinations that the state machine could never produce.
/// </summary>
public sealed record DictationSnapshot
{
    private DictationSnapshot(
        DictationPhase phase,
        Guid? generation = null,
        string? authoritativeText = null,
        string? outputText = null,
        OutputResult? output = null,
        VoxFlowError? error = null)
    {
        Validate(
            phase,
            generation,
            authoritativeText,
            outputText,
            output,
            error);

        Phase = phase;
        Generation = generation;
        AuthoritativeText = authoritativeText;
        OutputText = outputText;
        Output = output;
        Error = error;
    }

    public static DictationSnapshot Idle { get; } = new(DictationPhase.Idle);

    public DictationPhase Phase { get; }

    public Guid? Generation { get; }

    public string? AuthoritativeText { get; }

    public string? OutputText { get; }

    public OutputResult? Output { get; }

    public VoxFlowError? Error { get; }

    internal static DictationSnapshot Preparing(Guid generation) =>
        new(DictationPhase.Preparing, generation);

    internal DictationSnapshot ToRecording()
    {
        RequirePhase(DictationPhase.Preparing);
        return new DictationSnapshot(DictationPhase.Recording, Generation);
    }

    internal DictationSnapshot ToWaitingForFinal()
    {
        RequirePhase(DictationPhase.Recording);
        return new DictationSnapshot(DictationPhase.WaitingForFinal, Generation);
    }

    internal DictationSnapshot WithAuthoritativeFinal(string finalText)
    {
        RequirePhase(DictationPhase.WaitingForFinal);
        return new DictationSnapshot(
            DictationPhase.Processing,
            Generation,
            authoritativeText: finalText);
    }

    internal DictationSnapshot WithProcessedOutput(string outputText)
    {
        RequirePhase(DictationPhase.Processing);
        return new DictationSnapshot(
            DictationPhase.Injecting,
            Generation,
            AuthoritativeText,
            outputText);
    }

    internal DictationSnapshot WithCompletedOutput(OutputResult output)
    {
        RequirePhase(DictationPhase.Injecting);
        return new DictationSnapshot(
            DictationPhase.Completed,
            Generation,
            AuthoritativeText,
            OutputText,
            output);
    }

    internal DictationSnapshot WithFailure(
        VoxFlowError error,
        OutputResult? output = null)
    {
        if (Phase is DictationPhase.Idle or
            DictationPhase.Completed or
            DictationPhase.Failed)
        {
            throw new InvalidOperationException(
                $"A {Phase} snapshot cannot transition to failure.");
        }

        return new DictationSnapshot(
            DictationPhase.Failed,
            Generation,
            AuthoritativeText,
            OutputText,
            output,
            error);
    }

    private void RequirePhase(DictationPhase expected)
    {
        if (Phase != expected)
        {
            throw new InvalidOperationException(
                $"Snapshot phase {Phase} must be {expected}.");
        }
    }

    private static void Validate(
        DictationPhase phase,
        Guid? generation,
        string? authoritativeText,
        string? outputText,
        OutputResult? output,
        VoxFlowError? error)
    {
        if (phase == DictationPhase.Idle)
        {
            if (generation is not null ||
                authoritativeText is not null ||
                outputText is not null ||
                output is not null ||
                error is not null)
            {
                throw new ArgumentException("Idle snapshots cannot carry session data.");
            }

            return;
        }

        if (generation is null || generation == Guid.Empty)
        {
            throw new ArgumentException(
                "Non-idle snapshots require a non-empty generation.",
                nameof(generation));
        }

        switch (phase)
        {
            case DictationPhase.Preparing:
            case DictationPhase.Recording:
            case DictationPhase.WaitingForFinal:
                RequireAbsent(authoritativeText, outputText, output, error);
                break;
            case DictationPhase.Processing:
                RequireText(authoritativeText, nameof(authoritativeText));
                RequireAbsent(outputText, output, error);
                break;
            case DictationPhase.Injecting:
                RequireText(authoritativeText, nameof(authoritativeText));
                RequireText(outputText, nameof(outputText));
                RequireAbsent(output, error);
                break;
            case DictationPhase.Completed:
                RequireText(authoritativeText, nameof(authoritativeText));
                RequireText(outputText, nameof(outputText));
                ArgumentNullException.ThrowIfNull(output);
                if (error is not null)
                {
                    throw new ArgumentException(
                        "Completed snapshots cannot carry an error.",
                        nameof(error));
                }

                break;
            case DictationPhase.Failed:
                ArgumentNullException.ThrowIfNull(error);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(phase), phase, null);
        }
    }

    private static void RequireText(string? value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException(
                "Snapshot text must not be empty.",
                parameterName);
        }
    }

    private static void RequireAbsent(params object?[] values)
    {
        if (values.Any(value => value is not null))
        {
            throw new ArgumentException(
                "The snapshot carries data that is invalid for its phase.");
        }
    }
}
