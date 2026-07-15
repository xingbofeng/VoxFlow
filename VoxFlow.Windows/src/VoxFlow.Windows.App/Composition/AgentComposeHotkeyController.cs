using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Composition;

/// <summary>
/// Applies the Agent-specific short-press/hold gesture outside the keyboard
/// hook. The controller deliberately shares the existing dictation lifecycle;
/// it only decides when an Agent recording should start or stop.
/// </summary>
public sealed class AgentComposeHotkeyController
{
    private readonly AgentChordGestureRecognizer recognizer;
    private readonly Func<DictationPhase> phaseProvider;
    private readonly Func<CancellationToken, ValueTask> start;
    private readonly Func<CancellationToken, ValueTask> stop;
    private readonly Func<CancellationToken, ValueTask> cancel;
    private readonly Func<CancellationToken, ValueTask<AgentComposeReadinessInput>>? readiness;
    private readonly Action<AgentComposeReadinessResult>? readinessUnavailable;
    private readonly AgentComposeReadinessGate readinessGate = new();

    public AgentComposeHotkeyController(
        AgentChordGestureRecognizer recognizer,
        Func<DictationPhase> phaseProvider,
        Func<CancellationToken, ValueTask> start,
        Func<CancellationToken, ValueTask> stop,
        Func<CancellationToken, ValueTask> cancel,
        Func<CancellationToken, ValueTask<AgentComposeReadinessInput>>? readiness = null,
        Action<AgentComposeReadinessResult>? readinessUnavailable = null)
    {
        this.recognizer = recognizer ?? throw new ArgumentNullException(nameof(recognizer));
        this.phaseProvider = phaseProvider ?? throw new ArgumentNullException(nameof(phaseProvider));
        this.start = start ?? throw new ArgumentNullException(nameof(start));
        this.stop = stop ?? throw new ArgumentNullException(nameof(stop));
        this.cancel = cancel ?? throw new ArgumentNullException(nameof(cancel));
        this.readiness = readiness;
        this.readinessUnavailable = readinessUnavailable;
    }

    public ValueTask HandleAsync(
        InteractiveHotkeyRouteEvent routeEvent,
        CancellationToken cancellationToken = default) =>
        ExecuteAsync(recognizer.Handle(routeEvent, phaseProvider()), cancellationToken);

    public ValueTask AdvanceAsync(
        DateTimeOffset timestamp,
        CancellationToken cancellationToken = default) =>
        ExecuteAsync(recognizer.Advance(timestamp, phaseProvider()), cancellationToken);

    public ValueTask StartFromFirstPartyUiAsync(
        CancellationToken cancellationToken = default) =>
        StartIfReadyAsync(cancellationToken);

    private ValueTask ExecuteAsync(
        HotkeyRouteAction action,
        CancellationToken cancellationToken) => action switch
        {
            HotkeyRouteAction.ToggleStart or HotkeyRouteAction.HoldStart =>
                StartIfReadyAsync(cancellationToken),
            HotkeyRouteAction.ToggleStop or HotkeyRouteAction.HoldStop => stop(cancellationToken),
            HotkeyRouteAction.Cancel => cancel(cancellationToken),
            HotkeyRouteAction.None or HotkeyRouteAction.IgnoredBusy => ValueTask.CompletedTask,
            _ => throw new ArgumentOutOfRangeException(nameof(action), action, null),
        };

    private async ValueTask StartIfReadyAsync(CancellationToken cancellationToken)
    {
        if (readiness is not null)
        {
            var input = await readiness(cancellationToken).ConfigureAwait(false);
            var result = readinessGate.Evaluate(input);
            if (!result.CanStartRecording)
            {
                readinessUnavailable?.Invoke(result);
                return;
            }
        }

        await start(cancellationToken).ConfigureAwait(false);
    }
}
