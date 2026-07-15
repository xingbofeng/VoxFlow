using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Composition;

public sealed class DictationHotkeyController
{
    private readonly HotkeyInputRouter router;
    private readonly Func<DictationPhase> phaseProvider;
    private readonly Func<CancellationToken, ValueTask> start;
    private readonly Func<CancellationToken, ValueTask> stop;

    public DictationHotkeyController(
        HotkeyInputRouter router,
        Func<DictationPhase> phaseProvider,
        Func<CancellationToken, ValueTask> start,
        Func<CancellationToken, ValueTask> stop)
    {
        this.router = router ?? throw new ArgumentNullException(nameof(router));
        this.phaseProvider = phaseProvider
            ?? throw new ArgumentNullException(nameof(phaseProvider));
        this.start = start ?? throw new ArgumentNullException(nameof(start));
        this.stop = stop ?? throw new ArgumentNullException(nameof(stop));
    }

    public ValueTask HandleKeyAsync(
        LowLevelKeyEvent keyEvent,
        CancellationToken cancellationToken = default) => ExecuteAsync(
        router.HandleKey(keyEvent, HotkeyModifiers.None, phaseProvider()),
        cancellationToken);

    public ValueTask AdvanceAsync(
        DateTimeOffset timestamp,
        CancellationToken cancellationToken = default) => ExecuteAsync(
        router.AdvanceHybrid(timestamp, phaseProvider()),
        cancellationToken);

    public ValueTask HandleMatchedKeyAsync(
        KeyTransition transition,
        CancellationToken cancellationToken = default) => ExecuteAsync(
        router.HandleMatchedKey(transition, phaseProvider()),
        cancellationToken);

    public ValueTask HandleMouseAsync(
        MouseButton button,
        ButtonTransition transition,
        CancellationToken cancellationToken = default) => ExecuteAsync(
        router.HandleMouse(button, transition, phaseProvider()),
        cancellationToken);

    public void UpdateSettings(HotkeyRouteSettings settings) =>
        router.UpdateSettings(settings);

    private ValueTask ExecuteAsync(
        HotkeyRouteAction action,
        CancellationToken cancellationToken) => action switch
        {
            HotkeyRouteAction.ToggleStart or HotkeyRouteAction.HoldStart =>
                start(cancellationToken),
            HotkeyRouteAction.ToggleStop or HotkeyRouteAction.HoldStop =>
                stop(cancellationToken),
            HotkeyRouteAction.None or HotkeyRouteAction.IgnoredBusy =>
                ValueTask.CompletedTask,
            _ => throw new ArgumentOutOfRangeException(nameof(action), action, null),
        };
}
