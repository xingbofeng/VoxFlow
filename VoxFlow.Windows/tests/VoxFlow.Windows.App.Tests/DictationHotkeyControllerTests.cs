using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Tests;

public sealed class DictationHotkeyControllerTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 12, 2, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Short_right_control_press_starts_toggle_dictation()
    {
        var session = new FakeSession();
        var controller = CreateController(session);

        await controller.HandleKeyAsync(RightControl(KeyTransition.Down, Now));
        await controller.HandleKeyAsync(
            RightControl(KeyTransition.Up, Now.AddMilliseconds(120)));

        Assert.Equal(1, session.StartCount);
        Assert.Equal(0, session.StopCount);
    }

    // Composition boundary: controller + real HotkeyInputRouter after terminal
    // stop (Failed/Completed, e.g. Tencent empty-final). Must call start, not
    // stay dead on IgnoredBusy.
    [Theory]
    [InlineData(DictationPhase.Failed)]
    [InlineData(DictationPhase.Completed)]
    public async Task Short_right_control_after_terminal_phase_starts_dictation(
        DictationPhase terminalPhase)
    {
        var session = new FakeSession { Phase = terminalPhase };
        var controller = CreateController(session);

        await controller.HandleKeyAsync(RightControl(KeyTransition.Down, Now));
        await controller.HandleKeyAsync(
            RightControl(KeyTransition.Up, Now.AddMilliseconds(120)));

        Assert.Equal(1, session.StartCount);
        Assert.Equal(DictationPhase.Recording, session.Phase);
    }

    [Fact]
    public async Task Long_right_control_press_starts_and_release_stops_dictation()
    {
        var session = new FakeSession();
        var controller = CreateController(session);

        await controller.HandleKeyAsync(RightControl(KeyTransition.Down, Now));
        await controller.AdvanceAsync(Now.AddMilliseconds(600));
        await controller.HandleKeyAsync(
            RightControl(KeyTransition.Up, Now.AddMilliseconds(650)));

        Assert.Equal(1, session.StartCount);
        Assert.Equal(1, session.StopCount);
    }

    [Fact]
    public async Task Hold_release_stops_while_provider_start_is_still_preparing()
    {
        var session = new FakeSession { BlockStart = true };
        var controller = CreateController(session);

        await controller.HandleKeyAsync(RightControl(KeyTransition.Down, Now));
        var pendingStart = controller.AdvanceAsync(Now.AddMilliseconds(600)).AsTask();
        await session.StartEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));

        await controller.HandleKeyAsync(
            RightControl(KeyTransition.Up, Now.AddMilliseconds(650)));
        session.ReleaseStart();
        await pendingStart.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal(1, session.StartCount);
        Assert.Equal(1, session.StopCount);
        Assert.Equal(DictationPhase.Completed, session.Phase);
    }

    [Fact]
    public async Task Agent_short_press_toggles_the_agent_recording_lifecycle()
    {
        var session = new FakeSession();
        var controller = new AgentComposeHotkeyController(
            new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
            () => session.Phase,
            session.StartAsync,
            session.StopAsync,
            session.CancelAsync);

        await controller.HandleAsync(Agent(KeyTransition.Down, Now));
        await controller.HandleAsync(Agent(KeyTransition.Up, Now.AddMilliseconds(120)));
        await controller.HandleAsync(Agent(KeyTransition.Down, Now.AddMilliseconds(300)));
        await controller.HandleAsync(Agent(KeyTransition.Up, Now.AddMilliseconds(420)));

        Assert.Equal(1, session.StartCount);
        Assert.Equal(1, session.StopCount);
    }

    [Fact]
    public async Task Agent_hold_starts_after_threshold_and_stops_on_a_release()
    {
        var session = new FakeSession();
        var controller = new AgentComposeHotkeyController(
            new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
            () => session.Phase,
            session.StartAsync,
            session.StopAsync,
            session.CancelAsync);

        await controller.HandleAsync(Agent(KeyTransition.Down, Now));
        await controller.AdvanceAsync(Now.AddMilliseconds(500));
        await controller.HandleAsync(Agent(KeyTransition.Up, Now.AddMilliseconds(600)));

        Assert.Equal(1, session.StartCount);
        Assert.Equal(1, session.StopCount);
    }

    [Fact]
    public async Task Agent_chord_cancels_an_active_processing_run_without_waiting_for_key_up()
    {
        var session = new FakeSession { Phase = DictationPhase.Processing };
        var controller = new AgentComposeHotkeyController(
            new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
            () => session.Phase,
            session.StartAsync,
            session.StopAsync,
            session.CancelAsync);

        await controller.HandleAsync(Agent(KeyTransition.Down, Now));

        Assert.Equal(1, session.CancelCount);
        Assert.Equal(0, session.StopCount);
    }

    [Theory]
    [InlineData(false, AsrProviderAvailability.Ready, true, LlmAgentCapabilityStatus.Supported, AgentComposeReadinessStatus.SidecarUnavailable)]
    [InlineData(true, AsrProviderAvailability.Unconfigured, true, LlmAgentCapabilityStatus.Supported, AgentComposeReadinessStatus.AsrUnavailable)]
    [InlineData(true, AsrProviderAvailability.Ready, false, LlmAgentCapabilityStatus.Supported, AgentComposeReadinessStatus.DefaultProviderUnavailable)]
    [InlineData(true, AsrProviderAvailability.Ready, true, LlmAgentCapabilityStatus.Unsupported, AgentComposeReadinessStatus.AgentCapabilityUnavailable)]
    public async Task Agent_hotkey_checks_runtime_ASR_provider_and_tool_calling_before_recording(
        bool sidecarAvailable,
        AsrProviderAvailability asrAvailability,
        bool hasDefaultProvider,
        LlmAgentCapabilityStatus capability,
        AgentComposeReadinessStatus expected)
    {
        var session = new FakeSession();
        AgentComposeReadinessResult? feedback = null;
        var controller = new AgentComposeHotkeyController(
            new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
            () => session.Phase,
            session.StartAsync,
            session.StopAsync,
            session.CancelAsync,
            _ => ValueTask.FromResult(new AgentComposeReadinessInput(
                sidecarAvailable,
                asrAvailability,
                hasDefaultProvider,
                capability)),
            value => feedback = value);

        await controller.HandleAsync(Agent(KeyTransition.Down, Now));
        await controller.HandleAsync(Agent(KeyTransition.Up, Now.AddMilliseconds(120)));

        Assert.Equal(0, session.StartCount);
        Assert.Equal(expected, feedback?.Status);
    }

    [Fact]
    public async Task Agent_tray_and_hotkey_share_the_same_ready_start_boundary()
    {
        var session = new FakeSession();
        var readinessCalls = 0;
        var controller = new AgentComposeHotkeyController(
            new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
            () => session.Phase,
            session.StartAsync,
            session.StopAsync,
            session.CancelAsync,
            _ =>
            {
                readinessCalls++;
                return ValueTask.FromResult(new AgentComposeReadinessInput(
                    true,
                    AsrProviderAvailability.Ready,
                    true,
                    LlmAgentCapabilityStatus.Supported));
            });

        await controller.StartFromFirstPartyUiAsync();

        Assert.Equal(1, readinessCalls);
        Assert.Equal(1, session.StartCount);
    }

    private static DictationHotkeyController CreateController(FakeSession session) =>
        new(
            new HotkeyInputRouter(HotkeyRouteSettings.Default),
            () => session.Phase,
            session.StartAsync,
            session.StopAsync);

    private static LowLevelKeyEvent RightControl(
        KeyTransition transition,
        DateTimeOffset timestamp) => new(
        RightControlKeyClassifier.VirtualKeyRightControl,
        RightControlKeyClassifier.ControlScanCode,
        LowLevelKeyFlags.Extended,
        transition,
        timestamp);

    private static InteractiveHotkeyRouteEvent Agent(
        KeyTransition transition,
        DateTimeOffset timestamp) => new(
        InteractiveHotkeyAction.AgentCompose,
        transition,
        timestamp);

    private sealed class FakeSession
    {
        private readonly TaskCompletionSource startCompletion = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public DictationPhase Phase { get; set; } = DictationPhase.Idle;

        public bool BlockStart { get; set; }

        public TaskCompletionSource StartEntered { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public int StartCount { get; private set; }

        public int StopCount { get; private set; }

        public int CancelCount { get; private set; }

        public async ValueTask StartAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            StartCount++;
            Phase = DictationPhase.Preparing;
            StartEntered.TrySetResult();
            if (BlockStart)
            {
                await startCompletion.Task.WaitAsync(cancellationToken);
            }

            if (Phase == DictationPhase.Preparing)
            {
                Phase = DictationPhase.Recording;
            }
        }

        public void ReleaseStart() => startCompletion.TrySetResult();

        public ValueTask StopAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            StopCount++;
            Phase = DictationPhase.Completed;
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CancelCount++;
            Phase = DictationPhase.Idle;
            return ValueTask.CompletedTask;
        }
    }
}
