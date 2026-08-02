using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Output;

public sealed record ForegroundTargetIdentity
{
    public ForegroundTargetIdentity(
        int processId,
        string processPath,
        nint windowHandle,
        string windowTitle)
    {
        if (processId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(processId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(processPath);
        ProcessId = processId;
        ProcessPath = processPath;
        WindowHandle = windowHandle;
        WindowTitle = windowTitle ?? string.Empty;
    }

    public int ProcessId { get; init; }

    public string ProcessPath { get; init; }

    public nint WindowHandle { get; init; }

    public string WindowTitle { get; init; }
}

public enum ForegroundTargetComparison
{
    SameTarget,
    OriginalUnavailable,
    OriginalNoLongerExists,
    OriginalLivenessUnknown,
    TargetChanged,
    CurrentUnavailable,
}

public enum ForegroundTargetLiveness
{
    Exists,
    Missing,
    Unknown,
}

public static class ForegroundTargetComparer
{
    public static ForegroundTargetComparison Compare(
        ForegroundTargetIdentity original,
        ForegroundTargetIdentity? current,
        ForegroundTargetLiveness originalLiveness)
    {
        ArgumentNullException.ThrowIfNull(original);
        if (originalLiveness == ForegroundTargetLiveness.Missing)
        {
            return ForegroundTargetComparison.OriginalNoLongerExists;
        }

        if (originalLiveness == ForegroundTargetLiveness.Unknown)
        {
            return ForegroundTargetComparison.OriginalLivenessUnknown;
        }

        if (originalLiveness != ForegroundTargetLiveness.Exists)
        {
            throw new ArgumentOutOfRangeException(
                nameof(originalLiveness),
                originalLiveness,
                null);
        }

        if (current is null)
        {
            return ForegroundTargetComparison.CurrentUnavailable;
        }

        if (original.ProcessId != current.ProcessId
            || !string.Equals(
                NormalizePath(original.ProcessPath),
                NormalizePath(current.ProcessPath),
                StringComparison.OrdinalIgnoreCase))
        {
            return ForegroundTargetComparison.TargetChanged;
        }

        if (original.WindowHandle != nint.Zero
            && current.WindowHandle != nint.Zero
            && original.WindowHandle != current.WindowHandle)
        {
            return ForegroundTargetComparison.TargetChanged;
        }

        return ForegroundTargetComparison.SameTarget;
    }

    private static string NormalizePath(string path) =>
        path.Replace('/', '\\').TrimEnd('\\');
}

public enum TargetAwareOutputAction
{
    Inject,
    Copy,
}

public sealed record TargetAwareOutputDecision(
    TargetAwareOutputAction Action,
    ForegroundTargetComparison Comparison,
    OutputResult? Result = null);

public static class TargetAwareOutputPolicy
{
    public static TargetAwareOutputDecision Decide(
        ForegroundTargetComparison comparison) => comparison switch
        {
            ForegroundTargetComparison.SameTarget or
                ForegroundTargetComparison.OriginalNoLongerExists =>
                new(TargetAwareOutputAction.Inject, comparison),
            ForegroundTargetComparison.OriginalUnavailable or
                ForegroundTargetComparison.OriginalLivenessUnknown or
                ForegroundTargetComparison.TargetChanged or
                ForegroundTargetComparison.CurrentUnavailable =>
                new(
                    TargetAwareOutputAction.Copy,
                    comparison,
                    new OutputResult(
                        OutputResultKind.TargetChanged,
                        VoxFlowErrorCode.TargetChanged)),
            _ => throw new ArgumentOutOfRangeException(nameof(comparison), comparison, null),
        };
}

public sealed class ForegroundTargetOutputGuard
{
    private readonly IForegroundTargetProvider provider;

    public ForegroundTargetOutputGuard(IForegroundTargetProvider provider)
    {
        this.provider = provider ?? throw new ArgumentNullException(nameof(provider));
    }

    public ForegroundTargetIdentity? CaptureOriginal() => provider.CaptureCurrent();

    public TargetAwareOutputDecision DecideBeforeOutput(ForegroundTargetIdentity? original)
    {
        if (original is null)
        {
            return TargetAwareOutputPolicy.Decide(
                ForegroundTargetComparison.OriginalUnavailable);
        }

        var current = provider.CaptureCurrent();
        var comparison = ForegroundTargetComparer.Compare(
            original,
            current,
            provider.GetLiveness(original));
        return TargetAwareOutputPolicy.Decide(comparison);
    }
}

public interface IForegroundTargetProvider
{
    ForegroundTargetIdentity? CaptureCurrent();

    ForegroundTargetLiveness GetLiveness(ForegroundTargetIdentity target);
}
