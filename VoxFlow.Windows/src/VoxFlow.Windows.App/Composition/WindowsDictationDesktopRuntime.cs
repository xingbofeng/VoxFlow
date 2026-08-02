using System.Windows.Threading;
using VoxFlow.Windows.App.Diagnostics;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Audio;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.App.Composition;

public sealed class WindowsDictationDesktopRuntime : IAsyncDisposable
{
    private static readonly TimeSpan GestureTick = TimeSpan.FromMilliseconds(40);

    private readonly Dispatcher dispatcher;
    private readonly DictationOrchestrator orchestrator;
    private readonly WasapiDictationAudioCaptureAdapter audio;
    private readonly WindowsClipboardGateway clipboard;
    private readonly WindowsLowLevelKeyboardHook keyboardHook;
    private readonly WindowsLowLevelMouseHook mouseHook;
    private readonly ScreenshotKeyboardHookRouter screenshotKeyboardRouter;
    private readonly LowLevelKeyboardHookSupervisor hookSupervisor;
    private readonly DictationHotkeyController hotkeyController;
    private readonly DictationOrchestrator? agentOrchestrator;
    private readonly WasapiDictationAudioCaptureAdapter? agentAudio;
    private readonly WindowsClipboardGateway? agentClipboard;
    private readonly AgentComposeHotkeyController? agentHotkeyController;
    private readonly Action? agentCancellationRecorded;
    private readonly Func<CancellationToken, ValueTask<AgentComposeReadinessInput>>? agentReadiness;
    private readonly Action<AgentComposeReadinessResult>? agentReadinessUnavailable;
    private readonly Func<bool> foregroundInteractionBusy;
    private readonly Func<HotkeyRouteSettings>? hotkeySettingsProvider;
    private readonly InteractiveHotkeyRoute? interactiveRoute;
    private readonly Func<InteractiveHotkeyRouteEvent, CancellationToken, Task>? interactiveAction;
    private readonly DispatcherTimer gestureTimer;
    private readonly StartupDiagnosticLog diagnostics;
    private int disposed;

    public WindowsDictationDesktopRuntime(
        Dispatcher dispatcher,
        DictationOrchestrator orchestrator,
        WasapiDictationAudioCaptureAdapter audio,
        WindowsClipboardGateway clipboard,
        HotkeyRouteSettings hotkeySettings,
        StartupDiagnosticLog diagnostics,
        InteractiveHotkeyRoute? interactiveRoute = null,
        Func<InteractiveHotkeyRouteEvent, CancellationToken, Task>? interactiveAction = null,
        DictationOrchestrator? agentOrchestrator = null,
        WasapiDictationAudioCaptureAdapter? agentAudio = null,
        WindowsClipboardGateway? agentClipboard = null,
        Action? agentCancellationRecorded = null,
        Func<CancellationToken, ValueTask<AgentComposeReadinessInput>>? agentReadiness = null,
        Action<AgentComposeReadinessResult>? agentReadinessUnavailable = null,
        Func<bool>? foregroundInteractionBusy = null,
        ScreenshotKeyboardHookRouter? screenshotKeyboardRouter = null,
        Func<HotkeyRouteSettings>? hotkeySettingsProvider = null)
    {
        this.dispatcher = dispatcher
            ?? throw new ArgumentNullException(nameof(dispatcher));
        this.orchestrator = orchestrator
            ?? throw new ArgumentNullException(nameof(orchestrator));
        this.audio = audio ?? throw new ArgumentNullException(nameof(audio));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.diagnostics = diagnostics
            ?? throw new ArgumentNullException(nameof(diagnostics));
        if ((interactiveRoute is null) != (interactiveAction is null))
        {
            throw new ArgumentException("Interactive route and handler must be supplied together.");
        }
        this.interactiveRoute = interactiveRoute;
        this.interactiveAction = interactiveAction;
        if ((agentOrchestrator is null) != (agentAudio is null)
            || (agentOrchestrator is null) != (agentClipboard is null))
        {
            throw new ArgumentException(
                "Agent orchestrator, audio, and clipboard must be supplied together.");
        }
        this.agentOrchestrator = agentOrchestrator;
        this.agentAudio = agentAudio;
        this.agentClipboard = agentClipboard;
        this.agentCancellationRecorded = agentCancellationRecorded;
        this.agentReadiness = agentReadiness;
        this.agentReadinessUnavailable = agentReadinessUnavailable;
        this.foregroundInteractionBusy = foregroundInteractionBusy ?? (() => false);
        this.hotkeySettingsProvider = hotkeySettingsProvider;
        this.screenshotKeyboardRouter = screenshotKeyboardRouter
            ?? new ScreenshotKeyboardHookRouter();

        hotkeyController = new DictationHotkeyController(
            new HotkeyInputRouter(hotkeySettings),
            () => orchestrator.Snapshot.Phase,
            StartDictationAsync,
            StopDictationAsync);
        if (agentOrchestrator is not null)
        {
            agentHotkeyController = new AgentComposeHotkeyController(
                new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
                () => agentOrchestrator.Snapshot.Phase,
                StartAgentAsync,
                agentOrchestrator.StopAsync,
                CancelAgentAsync,
                agentReadiness,
                agentReadinessUnavailable);
        }
        keyboardHook = new WindowsLowLevelKeyboardHook(
            OnKeyEvent,
            this.screenshotKeyboardRouter.Route);
        mouseHook = new WindowsLowLevelMouseHook(
            OnMouseEvent,
            () => (this.hotkeySettingsProvider?.Invoke() ?? hotkeySettings)
                .MiddleMouseEnabled);
        hookSupervisor = new LowLevelKeyboardHookSupervisor(
            keyboardHook,
            new DiagnosticHotkeyFeedbackSink(diagnostics));
        gestureTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher)
        {
            Interval = GestureTick,
            IsEnabled = false,
        };
        gestureTimer.Tick += OnGestureTimerTick;
    }

    public bool Start()
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        var installed = hookSupervisor.Start();
        var mouseInstalled = mouseHook.TryInstall();
        diagnostics.Record(installed
            ? "hotkey.hook_installed"
            : "hotkey.hook_unavailable");
        diagnostics.Record(mouseInstalled
            ? "hotkey.mouse_hook_installed"
            : "hotkey.mouse_hook_unavailable");
        if (installed)
        {
            gestureTimer.Start();
        }
        return installed;
    }

    public bool IsVoiceWorkflowActive =>
        orchestrator.Snapshot.Phase != DictationPhase.Idle
        || agentOrchestrator?.Snapshot.Phase is not null and not DictationPhase.Idle;

    /// <summary>Starts Agent Compose from a first-party UI entry point. This
    /// keeps the tray on the same lifecycle guard as the global hotkey.</summary>
    public ValueTask StartAgentComposeAsync(CancellationToken cancellationToken = default) =>
        agentHotkeyController?.StartFromFirstPartyUiAsync(cancellationToken)
        ?? ReportAgentUnavailableAsync(cancellationToken);

    /// <summary>Stops the active Agent Compose run. A tray stop is an explicit
    /// cancellation: it must not let a queued sidecar tool execute later.</summary>
    public ValueTask StopAgentComposeAsync(CancellationToken cancellationToken = default) =>
        CancelAgentAsync(cancellationToken);

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        gestureTimer.Stop();
        gestureTimer.Tick -= OnGestureTimerTick;
        hookSupervisor.Dispose();
        mouseHook.Dispose();
        await orchestrator.DisposeAsync().ConfigureAwait(false);
        await audio.DisposeAsync().ConfigureAwait(false);
        clipboard.Dispose();
        if (agentOrchestrator is not null)
        {
            agentCancellationRecorded?.Invoke();
            await agentOrchestrator.DisposeAsync().ConfigureAwait(false);
            await agentAudio!.DisposeAsync().ConfigureAwait(false);
            agentClipboard!.Dispose();
        }
    }

    private void OnKeyEvent(LowLevelKeyboardDispatch dispatch)
    {
        if (dispatch.Consumed)
        {
            if (dispatch.ScreenshotCommand is { } screenshotCommand)
            {
                _ = dispatcher.BeginInvoke(
                    DispatcherPriority.Input,
                    new Action(() => RunSafelyAsync(() =>
                    {
                        screenshotKeyboardRouter.Dispatch(screenshotCommand);
                        return Task.CompletedTask;
                    })));
            }
            return;
        }
        _ = dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            new Action(() => RunSafelyAsync(() => HandleKeyAsync(dispatch.KeyEvent))));
    }

    private async Task HandleKeyAsync(LowLevelKeyEvent keyEvent)
    {
        if (hotkeySettingsProvider is not null)
        {
            hotkeyController.UpdateSettings(hotkeySettingsProvider());
        }

        if (keyEvent is { VirtualKey: 0x1B, Transition: KeyTransition.Down }
            && agentOrchestrator?.Snapshot.Phase is not null and not DictationPhase.Idle)
        {
            await CancelAgentAsync(CancellationToken.None).ConfigureAwait(true);
            return;
        }

        var interactive = interactiveRoute?.Handle(keyEvent);
        if (interactive is not null)
        {
            if (interactive.Action == InteractiveHotkeyAction.Dictation)
            {
                await hotkeyController
                    .HandleMatchedKeyAsync(interactive.Transition, CancellationToken.None)
                    .ConfigureAwait(true);
                return;
            }
            if (interactive.Action == InteractiveHotkeyAction.AgentCompose)
            {
                if (agentHotkeyController is not null)
                {
                    await agentHotkeyController
                        .HandleAsync(interactive, CancellationToken.None)
                        .ConfigureAwait(true);
                }
                else if (interactive.Transition == KeyTransition.Down)
                {
                    await ReportAgentUnavailableAsync(CancellationToken.None)
                        .ConfigureAwait(true);
                }
                return;
            }
            if (interactive.Transition == KeyTransition.Down)
            {
                await interactiveAction!(interactive, CancellationToken.None).ConfigureAwait(true);
            }
            return;
        }
        await hotkeyController.HandleKeyAsync(keyEvent).ConfigureAwait(true);
    }

    private void OnMouseEvent(MouseButton button, ButtonTransition transition) =>
        _ = dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            new Action(() => RunSafelyAsync(() => HandleMouseAsync(button, transition))));

    private async Task HandleMouseAsync(MouseButton button, ButtonTransition transition)
    {
        if (hotkeySettingsProvider is not null)
        {
            hotkeyController.UpdateSettings(hotkeySettingsProvider());
        }
        await hotkeyController
            .HandleMouseAsync(button, transition, CancellationToken.None)
            .ConfigureAwait(true);
    }

    public void UpdateHotkeySettings(HotkeyRouteSettings settings) =>
        hotkeyController.UpdateSettings(settings);

    private void OnGestureTimerTick(object? sender, EventArgs e) =>
        RunSafelyAsync(async () =>
        {
            var now = DateTimeOffset.UtcNow;
            await hotkeyController.AdvanceAsync(now).ConfigureAwait(true);
            if (agentHotkeyController is not null)
            {
                await agentHotkeyController.AdvanceAsync(now).ConfigureAwait(true);
            }
        });

    private async ValueTask StartDictationAsync(CancellationToken cancellationToken)
    {
        if (foregroundInteractionBusy()
            || agentOrchestrator?.Snapshot.Phase is not null and not DictationPhase.Idle)
        {
            diagnostics.Record(foregroundInteractionBusy()
                ? "dictation.blocked_foreground_interaction"
                : "dictation.blocked_agent_active");
            return;
        }

        try
        {
            var outcome = await orchestrator.StartAsync(cancellationToken)
                .ConfigureAwait(false);
            diagnostics.Record(
                $"dictation.start outcome={outcome} phase={orchestrator.Snapshot.Phase}");
        }
        catch (OperationCanceledException)
        {
            diagnostics.Record("dictation.start cancelled");
        }
        catch (Exception exception)
        {
            diagnostics.Record("dictation.start failed", exception);
        }
    }

    private async ValueTask StopDictationAsync(CancellationToken cancellationToken)
    {
        try
        {
            diagnostics.Record(
                $"dictation.stop begin phase={orchestrator.Snapshot.Phase}");
            await orchestrator.StopAsync(cancellationToken).ConfigureAwait(false);
            var snapshot = orchestrator.Snapshot;
            diagnostics.Record(
                $"dictation.stop completed phase={snapshot.Phase}" +
                $" error={snapshot.Error?.Code.ToString() ?? "none"}" +
                $" provider={snapshot.Error?.Provider?.ToString() ?? "none"}" +
                $" audioFrames={audio.CapturedFrameCount}" +
                $" audioBytes={audio.CapturedByteCount}");
        }
        catch (OperationCanceledException)
        {
            diagnostics.Record("dictation.stop cancelled");
        }
        catch (Exception exception)
        {
            diagnostics.Record("dictation.stop failed", exception);
            try
            {
                await orchestrator.CancelAsync(CancellationToken.None)
                    .ConfigureAwait(false);
                diagnostics.Record("dictation.stop fallback_cancel completed");
            }
            catch (Exception cancelException)
            {
                diagnostics.Record("dictation.stop fallback_cancel failed", cancelException);
            }
        }
    }

    private async ValueTask StartAgentAsync(CancellationToken cancellationToken)
    {
        if (foregroundInteractionBusy()
            || orchestrator.Snapshot.Phase != DictationPhase.Idle)
        {
            diagnostics.Record(foregroundInteractionBusy()
                ? "agent.blocked_foreground_interaction"
                : "agent.blocked_dictation_active");
            return;
        }
        _ = await agentOrchestrator!.StartAsync(cancellationToken).ConfigureAwait(false);
    }

    private async ValueTask CancelAgentAsync(CancellationToken cancellationToken)
    {
        if (agentOrchestrator is null || agentOrchestrator.Snapshot.Phase == DictationPhase.Idle)
        {
            return;
        }

        agentCancellationRecorded?.Invoke();
        await agentOrchestrator.CancelAsync(cancellationToken).ConfigureAwait(false);
    }

    private async ValueTask ReportAgentUnavailableAsync(
        CancellationToken cancellationToken)
    {
        diagnostics.Record("agent.hotkey_unavailable");
        if (agentReadiness is null)
        {
            return;
        }

        var input = await agentReadiness(cancellationToken).ConfigureAwait(false);
        var result = new AgentComposeReadinessGate().Evaluate(input);
        if (result.CanStartRecording)
        {
            result = new AgentComposeReadinessResult(
                AgentComposeReadinessStatus.SidecarUnavailable);
        }
        agentReadinessUnavailable?.Invoke(result);
    }

    private async void RunSafelyAsync(Func<Task> operation)
    {
        try
        {
            await operation().ConfigureAwait(true);
        }
        catch (OperationCanceledException)
        {
            // Normal application/session cancellation.
        }
        catch (Exception exception)
        {
            diagnostics.Record("hotkey.route_failed", exception);
        }
    }

    private sealed class DiagnosticHotkeyFeedbackSink(StartupDiagnosticLog diagnostics)
        : IHotkeyFeedbackSink
    {
        public void Report(HotkeyHealthFeedback feedback) => diagnostics.Record(
            feedback == HotkeyHealthFeedback.HookRecovered
                ? "hotkey.hook_recovered"
                : "hotkey.hook_unavailable");
    }
}

public sealed class DictationHistoryStoreSink : IDictationHistorySink
{
    private readonly HistoryRetentionService retention;
    private readonly Func<AsrSelection?> selectedAsr;

    public DictationHistoryStoreSink(
        IHistoryStore store,
        TimeProvider timeProvider,
        Func<AsrSelection?> selectedAsr)
    {
        retention = new HistoryRetentionService(
            store ?? throw new ArgumentNullException(nameof(store)),
            timeProvider ?? throw new ArgumentNullException(nameof(timeProvider)));
        this.selectedAsr = selectedAsr
            ?? throw new ArgumentNullException(nameof(selectedAsr));
    }

    public ValueTask SaveAsync(
        DictationHistoryDraft draft,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(draft);
        cancellationToken.ThrowIfCancellationRequested();
        var selection = selectedAsr();
        _ = retention.Record(
            new HistoryEntry(
                draft.Generation.ToString("N"),
                Source(selection),
                draft.RawText,
                draft.FinalText,
                new HistoryMetadata(
                    asrProvider: selection?.Provider,
                    qwenVariant: selection?.QwenVariant),
                draft.CreatedAtUtc),
            HistoryRetentionPolicy.Default);
        return ValueTask.CompletedTask;
    }

    private static string Source(AsrSelection? selection) => selection switch
    {
        { Provider: AsrProviderId.Qwen, QwenVariant: QwenVariant.Qwen06B } =>
            "qwen-0.6b",
        { Provider: AsrProviderId.Qwen, QwenVariant: QwenVariant.Qwen17B } =>
            "qwen-1.7b",
        { Provider: AsrProviderId.TencentCloud } => "tencent-cloud",
        { Provider: AsrProviderId.AliyunDashScope } => "aliyun-dashscope",
        { Provider: AsrProviderId.Volcengine } => "volcengine",
        _ => "unconfigured",
    };
}
