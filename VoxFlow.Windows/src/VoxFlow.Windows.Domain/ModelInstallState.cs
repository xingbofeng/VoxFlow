using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum ModelInstallPhase
{
    [JsonStringEnumMemberName("notDownloaded")]
    NotDownloaded,

    [JsonStringEnumMemberName("queued")]
    Queued,

    [JsonStringEnumMemberName("downloading")]
    Downloading,

    [JsonStringEnumMemberName("paused")]
    Paused,

    [JsonStringEnumMemberName("verifying")]
    Verifying,

    [JsonStringEnumMemberName("installing")]
    Installing,

    [JsonStringEnumMemberName("prewarming")]
    Prewarming,

    [JsonStringEnumMemberName("canaryTesting")]
    CanaryTesting,

    [JsonStringEnumMemberName("ready")]
    Ready,

    [JsonStringEnumMemberName("deleting")]
    Deleting,

    [JsonStringEnumMemberName("insufficientSpace")]
    InsufficientSpace,

    [JsonStringEnumMemberName("corrupted")]
    Corrupted,

    [JsonStringEnumMemberName("runtimeUnsupported")]
    RuntimeUnsupported,

    [JsonStringEnumMemberName("hardwareUnsupported")]
    HardwareUnsupported,

    [JsonStringEnumMemberName("failed")]
    Failed,
}

public static class ModelInstallTransitions
{
    private static readonly IReadOnlyDictionary<ModelInstallPhase, ISet<ModelInstallPhase>> Allowed =
        new Dictionary<ModelInstallPhase, ISet<ModelInstallPhase>>
        {
            [ModelInstallPhase.NotDownloaded] = Set(ModelInstallPhase.Queued),
            [ModelInstallPhase.Queued] = Set(
                ModelInstallPhase.Downloading,
                ModelInstallPhase.InsufficientSpace,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.Downloading] = Set(
                ModelInstallPhase.Paused,
                ModelInstallPhase.Verifying,
                ModelInstallPhase.InsufficientSpace,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.Paused] = Set(
                ModelInstallPhase.Downloading,
                ModelInstallPhase.Deleting,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.Verifying] = Set(
                ModelInstallPhase.Installing,
                ModelInstallPhase.Corrupted,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.Installing] = Set(
                ModelInstallPhase.Prewarming,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.Prewarming] = Set(
                ModelInstallPhase.CanaryTesting,
                ModelInstallPhase.RuntimeUnsupported,
                ModelInstallPhase.HardwareUnsupported,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.CanaryTesting] = Set(
                ModelInstallPhase.Ready,
                ModelInstallPhase.RuntimeUnsupported,
                ModelInstallPhase.HardwareUnsupported,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.Ready] = Set(ModelInstallPhase.Deleting),
            [ModelInstallPhase.Deleting] = Set(
                ModelInstallPhase.NotDownloaded,
                ModelInstallPhase.Failed),
            [ModelInstallPhase.InsufficientSpace] = Set(
                ModelInstallPhase.Queued,
                ModelInstallPhase.Deleting),
            [ModelInstallPhase.Corrupted] = Set(
                ModelInstallPhase.Queued,
                ModelInstallPhase.Deleting),
            [ModelInstallPhase.RuntimeUnsupported] = Set(ModelInstallPhase.Deleting),
            [ModelInstallPhase.HardwareUnsupported] = Set(ModelInstallPhase.Deleting),
            [ModelInstallPhase.Failed] = Set(
                ModelInstallPhase.Queued,
                ModelInstallPhase.Deleting),
        };

    public static bool CanMove(ModelInstallPhase current, ModelInstallPhase next) =>
        Allowed.TryGetValue(current, out var nextPhases) && nextPhases.Contains(next);

    public static void EnsureCanMove(ModelInstallPhase current, ModelInstallPhase next)
    {
        if (!CanMove(current, next))
        {
            throw new InvalidOperationException(
                $"Model install state cannot move from {current} to {next}.");
        }
    }

    private static ISet<ModelInstallPhase> Set(params ModelInstallPhase[] phases) =>
        phases.ToHashSet();
}
