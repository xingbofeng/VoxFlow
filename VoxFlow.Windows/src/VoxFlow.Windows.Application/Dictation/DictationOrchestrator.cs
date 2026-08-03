using System.Collections.Concurrent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Dictation;

/// <summary>
/// Owns one dictation generation at a time and coordinates short provider
/// callbacks with the asynchronous audio, processing, output, and history
/// pipeline. All lifecycle linearization happens through <see cref="lifecycleGate"/>;
/// provider callbacks only publish a partial or signal a terminal event.
/// </summary>
public sealed class DictationOrchestrator : IAsyncDisposable
{
    private static readonly TimeSpan PreparationTimeout = TimeSpan.FromSeconds(30);

    private readonly IDictationAsrProvider provider;
    private readonly IDictationAudioCapture audio;
    private readonly IDictationAudioFailureSource? audioFailureSource;
    private readonly IDictationTextPostProcessor processor;
    private readonly IDictationOutput output;
    private readonly IDictationHistorySink history;
    private readonly IDictationProgressSink progress;
    private readonly IDictationTargetCapture? targetCapture;
    private readonly TimeProvider timeProvider;
    private readonly TimeSpan finalTimeout;
    private readonly DictationStateMachine stateMachine = new();
    private readonly SemaphoreSlim lifecycleGate = new(1, 1);
    private readonly object callbackGate = new();
    private readonly ConcurrentDictionary<Guid, RunContext> contexts = new();
    private readonly TaskCompletionSource disposalCompleted = new(
        TaskCreationOptions.RunContinuationsAsynchronously);

    private RunContext? activeContext;
    private StartReservation? preparing;
    private bool disposed;

    public DictationOrchestrator(
        IDictationAsrProvider provider,
        IDictationAudioCapture audio,
        IDictationTextPostProcessor processor,
        IDictationOutput output,
        IDictationHistorySink history,
        IDictationProgressSink progress,
        TimeProvider timeProvider,
        TimeSpan finalTimeout,
        IDictationTargetCapture? targetCapture = null)
    {
        this.provider = provider ?? throw new ArgumentNullException(nameof(provider));
        this.audio = audio ?? throw new ArgumentNullException(nameof(audio));
        audioFailureSource = audio as IDictationAudioFailureSource;
        this.processor = processor ?? throw new ArgumentNullException(nameof(processor));
        this.output = output ?? throw new ArgumentNullException(nameof(output));
        this.history = history ?? throw new ArgumentNullException(nameof(history));
        this.progress = progress ?? throw new ArgumentNullException(nameof(progress));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        this.targetCapture = targetCapture ?? output as IDictationTargetCapture;

        if (finalTimeout <= TimeSpan.Zero
            || finalTimeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(
                nameof(finalTimeout),
                "The final-result timeout must be finite and positive.");
        }

        this.finalTimeout = finalTimeout;
        if (audioFailureSource is not null)
        {
            audioFailureSource.Failed += OnAudioFailure;
        }
    }

    public DictationSnapshot Snapshot => stateMachine.Snapshot;

    public async ValueTask<DictationStartOutcome> StartAsync(
        CancellationToken cancellationToken)
    {
        StartReservation reservation;
        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();

            lock (callbackGate)
            {
                if (preparing is not null
                    || activeContext is not null
                    || !contexts.IsEmpty)
                {
                    return DictationStartOutcome.AlreadyActive;
                }
            }

            ResetTerminalSnapshotIfNeeded();

            var unavailableOutcome = PublishProviderGuidanceIfUnavailable();
            if (unavailableOutcome is not null)
            {
                return unavailableOutcome.Value;
            }

            targetCapture?.CaptureOriginalTarget();

            var generation = Guid.NewGuid();
            reservation = new StartReservation(generation, cancellationToken);
            preparing = reservation;
            lock (callbackGate)
            {
                stateMachine.Begin(generation);
                PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
            }
        }
        finally
        {
            lifecycleGate.Release();
        }

        return await PrepareAsync(reservation).ConfigureAwait(false);
    }

    private async ValueTask<DictationStartOutcome> PrepareAsync(
        StartReservation reservation)
    {
        IDictationAsrSession? session = null;
        RunContext? context = null;
        try
        {
            session = await provider
                .CreateSessionAsync(reservation.Generation, reservation.Token)
                .ConfigureAwait(false)
                ?? throw new InvalidOperationException(
                    "The selected ASR provider returned no session.");
            reservation.Token.ThrowIfCancellationRequested();

            await lifecycleGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
            try
            {
                if (disposed
                    || !ReferenceEquals(preparing, reservation)
                    || reservation.Token.IsCancellationRequested)
                {
                    throw new OperationCanceledException(reservation.Token);
                }

                context = new RunContext(
                    this,
                    reservation.Generation,
                    session,
                    timeProvider,
                    reservation.TakeCancellation());
                if (!contexts.TryAdd(reservation.Generation, context))
                {
                    throw new InvalidOperationException(
                        "The dictation generation is already registered.");
                }

                preparing = null;
                lock (callbackGate)
                {
                    activeContext = context;
                }

                context.Subscribe();
                context.MarkAudioStartAttempted();
            }
            finally
            {
                lifecycleGate.Release();
            }

            try
            {
                await audio.StartAsync(
                        context.ForwardAudioAsync,
                        context.Token)
                    .ConfigureAwait(false);
                context.MarkAudioStartCompleted(started: true);
            }
            catch
            {
                context.MarkAudioStartCompleted(started: false);
                throw;
            }

            context.Token.ThrowIfCancellationRequested();
            using (var timeoutCancellation = new CancellationTokenSource(
                PreparationTimeout,
                timeProvider))
            using (var startCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                context.Token,
                timeoutCancellation.Token))
            {
                try
                {
                    await session.StartAsync(startCancellation.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException exception) when (
                    timeoutCancellation.IsCancellationRequested
                    && !context.Token.IsCancellationRequested)
                {
                    throw new TimeoutException(
                        "The selected ASR provider did not become ready in time.",
                        exception);
                }
            }
            context.Token.ThrowIfCancellationRequested();

            if (context.StopRequestedDuringPreparation)
            {
                await context.AudioStopCompleted.Task.ConfigureAwait(false);
                context.Token.ThrowIfCancellationRequested();
            }

            var startStopCore = false;
            var stoppedDuringPreparation = false;
            await lifecycleGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
            try
            {
                lock (callbackGate)
                {
                    if (!ReferenceEquals(activeContext, context))
                    {
                        throw new OperationCanceledException(context.Token);
                    }

                    stateMachine.Prepared();
                    PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                    // Queue pre-roll only after callbacks can observe Recording.
                    // Provider sends run asynchronously and never execute under
                    // callbackGate, so an early final cannot consume StopStarted
                    // while the state machine is still Preparing.
                    context.ActivateAudio();

                    stoppedDuringPreparation = context.StopRequestedDuringPreparation;
                    if (stoppedDuringPreparation)
                    {
                        stateMachine.StopRecording();
                        PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                        startStopCore = context.TryMarkStopStarted();
                    }
                }
            }
            finally
            {
                lifecycleGate.Release();
            }

            if (stoppedDuringPreparation)
            {
                await context.AudioStopCompleted.Task.ConfigureAwait(false);
            }

            if (startStopCore)
            {
                _ = RunStopCoreAsync(context);
            }

            return DictationStartOutcome.Started;
        }
        catch (OperationCanceledException) when (
            reservation.Token.IsCancellationRequested
            || context?.Token.IsCancellationRequested == true)
        {
            if (context is not null)
            {
                DetachActiveAsCancelled(context);
                await CancelAndDisposeContextAsync(context).ConfigureAwait(false);
            }
            else
            {
                await ClearPreparingReservationAsync(reservation, cancelled: true)
                    .ConfigureAwait(false);
                if (session is not null)
                {
                    await DisposeSessionSafelyAsync(session).ConfigureAwait(false);
                }
            }

            throw new OperationCanceledException(reservation.Token);
        }
        catch (DictationAudioCaptureException exception)
        {
            if (context is not null)
            {
                FailPreparingGeneration(context, exception.Error);
                await CancelAndDisposeContextAsync(context).ConfigureAwait(false);
            }
            else
            {
                await ClearPreparingReservationAsync(reservation, cancelled: false)
                    .ConfigureAwait(false);
                if (session is not null)
                {
                    await DisposeSessionSafelyAsync(session).ConfigureAwait(false);
                }
            }

            return DictationStartOutcome.Failed;
        }
        catch (Exception)
        {
            if (context is not null)
            {
                FailPreparingGeneration(context);
                await CancelAndDisposeContextAsync(context).ConfigureAwait(false);
            }
            else
            {
                await ClearPreparingReservationAsync(reservation, cancelled: false)
                    .ConfigureAwait(false);
                if (session is not null)
                {
                    await DisposeSessionSafelyAsync(session).ConfigureAwait(false);
                }
            }

            return DictationStartOutcome.Failed;
        }
        finally
        {
            reservation.DisposeIfUnclaimed();
        }
    }

    private async ValueTask ClearPreparingReservationAsync(
        StartReservation reservation,
        bool cancelled)
    {
        await lifecycleGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            if (ReferenceEquals(preparing, reservation))
            {
                preparing = null;
                if (cancelled)
                {
                    CancelPreparingGeneration(reservation.Generation);
                }
                else
                {
                    FailPreparingGeneration(reservation.Generation);
                }
            }
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    public async ValueTask StopAsync(CancellationToken cancellationToken)
    {
        RunContext? context = null;
        var cancelUncommittedPreparation = false;
        var stopDuringPreparation = false;
        var startStopCore = false;

        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();

            lock (callbackGate)
            {
                if (preparing is not null)
                {
                    // The provider has not returned a session yet, so there is
                    // no microphone stream or buffered utterance to finalize.
                    cancelUncommittedPreparation = true;
                }
                else
                {
                    context = activeContext;
                    if (context is null)
                    {
                        return;
                    }

                    if (stateMachine.Snapshot.Phase == DictationPhase.Preparing)
                    {
                        // Preserve hold-to-talk semantics while the cloud
                        // websocket is connecting: stop the microphone now,
                        // then flush the pre-roll and finish once ready.
                        context.RequestStopDuringPreparation();
                        stopDuringPreparation = true;
                    }
                    else
                    {
                        if (stateMachine.Snapshot.Phase == DictationPhase.Recording)
                        {
                            stateMachine.StopRecording();
                            PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                        }

                        startStopCore = context.TryMarkStopStarted();
                    }
                }
            }
        }
        finally
        {
            lifecycleGate.Release();
        }

        if (cancelUncommittedPreparation)
        {
            await CancelAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        if (stopDuringPreparation)
        {
            await StopAudioOnceAsync(context!).ConfigureAwait(false);
            await context!.Completion.Task
                .WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            return;
        }

        if (startStopCore)
        {
            _ = RunStopCoreAsync(context!);
        }

        await context!.Completion.Task
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
    }

    public async ValueTask CancelAsync(CancellationToken cancellationToken)
    {
        RunContext? context;
        RunContext? committedOutputContext = null;
        StartReservation? reservation;

        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();
            reservation = preparing;
            if (reservation is not null)
            {
                preparing = null;
                reservation.Cancel();
                CancelPreparingGeneration(reservation.Generation);
                context = null;
            }
            else
            {
                lock (callbackGate)
                {
                    if (activeContext?.OutputCommitStarted == true)
                    {
                        committedOutputContext = activeContext;
                        context = null;
                    }
                    else
                    {
                        context = DetachActiveAsCancelled();
                    }
                }
            }
        }
        finally
        {
            lifecycleGate.Release();
        }

        if (reservation is not null)
        {
            return;
        }

        if (committedOutputContext is not null)
        {
            await committedOutputContext.Completion.Task
                .WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            return;
        }

        if (context is null)
        {
            return;
        }

        context.Cancel();
        await StopAudioOnceAsync(context).ConfigureAwait(false);
        await CancelSessionOnceAsync(context).ConfigureAwait(false);

        if (context.StopStarted)
        {
            await context.Completion.Task.ConfigureAwait(false);
        }
        else
        {
            await CleanupContextAsync(context).ConfigureAwait(false);
            context.Completion.TrySetResult();
        }
    }

    public async ValueTask DisposeAsync()
    {
        RunContext[] remaining;
        StartReservation? reservation;
        var ownsDisposal = false;

        await lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (disposed)
            {
                reservation = null;
                remaining = [];
            }
            else
            {
                disposed = true;
                ownsDisposal = true;
                reservation = preparing;
                preparing = null;
                reservation?.Cancel();
                if (reservation is not null)
                {
                    CancelPreparingGeneration(reservation.Generation);
                }

                _ = DetachActiveAsCancelled();
                remaining = [.. contexts.Values];
            }
        }
        finally
        {
            lifecycleGate.Release();
        }

        if (!ownsDisposal)
        {
            await disposalCompleted.Task.ConfigureAwait(false);
            return;
        }

        try
        {
            foreach (var context in remaining)
            {
                context.Cancel();
            }

            foreach (var context in remaining)
            {
                await StopAudioOnceAsync(context).ConfigureAwait(false);
                await CancelSessionOnceAsync(context).ConfigureAwait(false);

                if (context.StopStarted)
                {
                    await context.Completion.Task.ConfigureAwait(false);
                }
                else
                {
                    await CleanupContextAsync(context).ConfigureAwait(false);
                    context.Completion.TrySetResult();
                }
            }
        }
        finally
        {
            if (ownsDisposal && audioFailureSource is not null)
            {
                audioFailureSource.Failed -= OnAudioFailure;
            }

            disposalCompleted.TrySetResult();
        }
    }

    private DictationStartOutcome? PublishProviderGuidanceIfUnavailable()
    {
        var availability = provider.Availability;
        if (availability == AsrProviderAvailability.Ready)
        {
            return null;
        }

        var guidance = availability switch
        {
            AsrProviderAvailability.Unconfigured => DictationGuidance.ConfigureAsr,
            AsrProviderAvailability.NotReady => DictationGuidance.PrepareSelectedProvider,
            _ => throw new ArgumentOutOfRangeException(nameof(availability), availability, null),
        };
        PublishSafely(new DictationProgressUpdate(Guidance: guidance));

        return availability == AsrProviderAvailability.Unconfigured
            ? DictationStartOutcome.NeedsConfiguration
            : DictationStartOutcome.ProviderNotReady;
    }

    private void ResetTerminalSnapshotIfNeeded()
    {
        lock (callbackGate)
        {
            if (stateMachine.Snapshot.Phase is
                DictationPhase.Completed or DictationPhase.Failed)
            {
                stateMachine.Reset();
            }
        }
    }

    private async Task RunStopCoreAsync(RunContext context)
    {
        try
        {
            await StopAudioOnceAsync(context).ConfigureAwait(false);
            await context.DrainAudioAsync().ConfigureAwait(false);
            context.Token.ThrowIfCancellationRequested();

            if (context.TryMarkFinishStarted())
            {
                await context.Session
                    .FinishAsync(context.Token)
                    .ConfigureAwait(false);
            }

            var timeoutTask = Task.Delay(
                finalTimeout,
                timeProvider,
                context.Token);
            await Task.WhenAny(context.Terminal.Task, timeoutTask).ConfigureAwait(false);
            context.Token.ThrowIfCancellationRequested();

            ProviderTerminal? terminal = context.Terminal.Task.IsCompletedSuccessfully
                ? await context.Terminal.Task.ConfigureAwait(false)
                : null;

            if (terminal?.Error is { } providerError)
            {
                await FailProviderAsync(context, providerError).ConfigureAwait(false);
                await CancelSessionOnceAsync(context).ConfigureAwait(false);
                return;
            }

            string? authoritativeText;
            await lifecycleGate.WaitAsync(context.Token).ConfigureAwait(false);
            try
            {
                lock (callbackGate)
                {
                    if (!ReferenceEquals(activeContext, context))
                    {
                        return;
                    }

                    var accepted = terminal?.FinalText is { } finalText
                        ? stateMachine.TryAcceptFinal(context.Generation, finalText)
                        : stateMachine.TryFinalTimedOut(context.Generation);
                    if (!accepted)
                    {
                        return;
                    }

                    PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                    if (stateMachine.Snapshot.Phase == DictationPhase.Failed)
                    {
                        activeContext = null;
                        authoritativeText = null;
                    }
                    else
                    {
                        authoritativeText = stateMachine.Snapshot.AuthoritativeText;
                    }
                }
            }
            finally
            {
                lifecycleGate.Release();
            }

            if (authoritativeText is null)
            {
                await CancelSessionOnceAsync(context).ConfigureAwait(false);
                return;
            }

            var processedText = await ProcessWithConservativeFallbackAsync(
                    context,
                    authoritativeText)
                .ConfigureAwait(false);
            context.Token.ThrowIfCancellationRequested();

            await lifecycleGate.WaitAsync(context.Token).ConfigureAwait(false);
            try
            {
                lock (callbackGate)
                {
                    if (!ReferenceEquals(activeContext, context)
                        || !stateMachine.TryProcessingCompleted(
                            context.Generation,
                            processedText))
                    {
                        return;
                    }

                    context.MarkOutputCommitStarted();
                    PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                }
            }
            finally
            {
                lifecycleGate.Release();
            }

            var outputResult = await output
                .WriteAsync(processedText, context.Token)
                .ConfigureAwait(false);
            context.Token.ThrowIfCancellationRequested();

            var shouldSaveHistory = false;
            await lifecycleGate.WaitAsync(context.Token).ConfigureAwait(false);
            try
            {
                lock (callbackGate)
                {
                    if (!ReferenceEquals(activeContext, context)
                        || !stateMachine.TryOutputCompleted(
                            context.Generation,
                            outputResult))
                    {
                        return;
                    }

                    PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                    activeContext = null;
                    shouldSaveHistory =
                        stateMachine.Snapshot.Phase is
                            DictationPhase.Completed or DictationPhase.Failed;
                }
            }
            finally
            {
                lifecycleGate.Release();
            }

            if (shouldSaveHistory)
            {
                await SaveHistorySafelyAsync(
                        context,
                        authoritativeText,
                        processedText,
                        outputResult)
                    .ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (context.Token.IsCancellationRequested)
        {
            // CancelAsync/DisposeAsync owns the visible Idle transition.
        }
        catch (Exception)
        {
            await FailOperationAsync(context).ConfigureAwait(false);
            await CancelSessionOnceAsync(context).ConfigureAwait(false);
        }
        finally
        {
            await CleanupContextAsync(context).ConfigureAwait(false);
            context.Completion.TrySetResult();
        }
    }

    private async ValueTask<string> ProcessWithConservativeFallbackAsync(
        RunContext context,
        string authoritativeText)
    {
        try
        {
            var processed = await processor.ProcessAsync(
                    authoritativeText,
                    new ProcessingProgress(this, context),
                    context.Token)
                .ConfigureAwait(false);

            return string.IsNullOrWhiteSpace(processed)
                ? authoritativeText
                : processed;
        }
        catch (OperationCanceledException) when (context.Token.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            if (processor is IDictationTextPostProcessorFailurePolicy
                { UseAuthoritativeTextOnFailure: false })
            {
                throw;
            }
            return authoritativeText;
        }
    }

    private async ValueTask PushAudioAsync(
        RunContext context,
        ReadOnlyMemory<byte> frame,
        CancellationToken frameCancellation)
    {
        if (frame.IsEmpty || !IsCurrentContext(context))
        {
            return;
        }

        if (frameCancellation.IsCancellationRequested
            || context.Token.IsCancellationRequested)
        {
            return;
        }

        await context.Session
            .PushAudioAsync(frame, frameCancellation)
            .ConfigureAwait(false);
    }

    private void OnAudioForwardingFailure(RunContext context, Exception exception)
    {
        if (exception is OperationCanceledException
            && context.Token.IsCancellationRequested)
        {
            return;
        }

        OnProviderFailure(
            context,
            new VoxFlowError(VoxFlowErrorCode.ProviderFailure));
    }

    private void OnPartial(RunContext context, AsrPartialResult partial)
    {
        if (string.IsNullOrWhiteSpace(partial.Text))
        {
            return;
        }

        lock (callbackGate)
        {
            if (!ReferenceEquals(activeContext, context)
                || stateMachine.Snapshot.Generation != context.Generation
                || stateMachine.Snapshot.Phase is not (
                    DictationPhase.Recording or DictationPhase.WaitingForFinal)
                || !context.TryAdvancePartialRevision(partial.Revision))
            {
                return;
            }

            PublishSafely(new DictationProgressUpdate(PartialText: partial.Text));
        }
    }

    private void OnFinal(RunContext context, AsrFinalResult final)
    {
        var accepted = false;
        lock (callbackGate)
        {
            if (ReferenceEquals(activeContext, context)
                && stateMachine.Snapshot.Generation == context.Generation)
            {
                accepted = context.Terminal.TrySetResult(
                    ProviderTerminal.FromFinal(final.Text));
            }
        }

        if (accepted)
        {
            QueueTerminalCoordinator(context);
        }
    }

    private void OnProviderFailure(RunContext context, VoxFlowError error)
    {
        var accepted = false;
        lock (callbackGate)
        {
            if (ReferenceEquals(activeContext, context)
                && stateMachine.Snapshot.Generation == context.Generation)
            {
                accepted = context.Terminal.TrySetResult(
                    ProviderTerminal.FromError(error));
            }
        }

        if (accepted)
        {
            QueueTerminalCoordinator(context);
        }
    }

    private void OnAudioFailure(object? sender, VoxFlowError error)
    {
        RunContext? context;
        var accepted = false;
        lock (callbackGate)
        {
            context = activeContext;
            if (context is not null
                && stateMachine.Snapshot.Generation == context.Generation
                && stateMachine.Snapshot.Phase is
                    DictationPhase.Preparing or DictationPhase.Recording)
            {
                accepted = context.Terminal.TrySetResult(
                    ProviderTerminal.FromError(error));
            }
        }

        if (accepted)
        {
            QueueTerminalCoordinator(context!);
        }
    }

    private void QueueTerminalCoordinator(RunContext context)
    {
        _ = Task.Run(async () =>
        {
            try
            {
                var terminal = await context.Terminal.Task.ConfigureAwait(false);
                if (terminal.Error is { } error)
                {
                    await FailProviderAsync(context, error).ConfigureAwait(false);
                    await StopAudioOnceAsync(context).ConfigureAwait(false);
                    await CancelSessionOnceAsync(context).ConfigureAwait(false);

                    if (!context.StopStarted)
                    {
                        await CleanupContextAsync(context).ConfigureAwait(false);
                        context.Completion.TrySetResult();
                    }
                }
                else
                {
                    await EnsureProviderFinalStopsRecordingAsync(context)
                        .ConfigureAwait(false);
                }
            }
            catch (Exception)
            {
                await FailOperationAsync(context).ConfigureAwait(false);
                await StopAudioOnceAsync(context).ConfigureAwait(false);
                await CancelSessionOnceAsync(context).ConfigureAwait(false);

                if (!context.StopStarted)
                {
                    await CleanupContextAsync(context).ConfigureAwait(false);
                    context.Completion.TrySetResult();
                }
            }
        });
    }

    private async Task EnsureProviderFinalStopsRecordingAsync(RunContext context)
    {
        var startStopCore = false;
        var stopDuringPreparation = false;
        await lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            lock (callbackGate)
            {
                if (!ReferenceEquals(activeContext, context))
                {
                    return;
                }

                if (stateMachine.Snapshot.Phase == DictationPhase.Preparing)
                {
                    context.RequestStopDuringPreparation();
                    stopDuringPreparation = true;
                }
                else
                {
                    if (stateMachine.Snapshot.Phase == DictationPhase.Recording)
                    {
                        stateMachine.StopRecording();
                        PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                    }

                    startStopCore = context.TryMarkStopStarted();
                }
            }
        }
        finally
        {
            lifecycleGate.Release();
        }

        if (stopDuringPreparation)
        {
            await StopAudioOnceAsync(context).ConfigureAwait(false);
            return;
        }

        if (startStopCore)
        {
            _ = RunStopCoreAsync(context);
        }
    }

    private async Task FailProviderAsync(RunContext context, VoxFlowError error)
    {
        await lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            lock (callbackGate)
            {
                if (!ReferenceEquals(activeContext, context)
                    || !stateMachine.TryFail(context.Generation, error))
                {
                    return;
                }

                PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                activeContext = null;
                context.Cancel();
            }
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    private async Task FailOperationAsync(RunContext context)
    {
        await lifecycleGate.WaitAsync().ConfigureAwait(false);
        try
        {
            lock (callbackGate)
            {
                if (!ReferenceEquals(activeContext, context))
                {
                    return;
                }

                var error = new VoxFlowError(VoxFlowErrorCode.Unknown);
                var failed = stateMachine.TryFail(context.Generation, error)
                    || stateMachine.TryOperationFailed(context.Generation, error);
                if (!failed)
                {
                    return;
                }

                PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
                activeContext = null;
                context.Cancel();
            }
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    private void PublishProcessingProgress(RunContext context, string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        lock (callbackGate)
        {
            if (!ReferenceEquals(activeContext, context)
                || stateMachine.Snapshot.Generation != context.Generation
                || stateMachine.Snapshot.Phase != DictationPhase.Processing)
            {
                return;
            }

            PublishSafely(new DictationProgressUpdate(ProcessingText: text));
        }
    }

    private RunContext? DetachActiveAsCancelled()
    {
        lock (callbackGate)
        {
            var context = activeContext;
            if (context is null)
            {
                return null;
            }

            activeContext = null;
            if (stateMachine.Snapshot.Phase is
                DictationPhase.Preparing or
                DictationPhase.Recording or
                DictationPhase.WaitingForFinal or
                DictationPhase.Processing or
                DictationPhase.Injecting)
            {
                stateMachine.Cancel();
                PublishSafely(new DictationProgressUpdate(
                    Snapshot: stateMachine.Snapshot,
                    PartialText: null,
                    ProcessingText: null));
            }

            return context;
        }
    }

    private void DetachActiveAsCancelled(RunContext context)
    {
        lock (callbackGate)
        {
            if (!ReferenceEquals(activeContext, context))
            {
                return;
            }

            activeContext = null;
            stateMachine.Cancel();
            PublishSafely(new DictationProgressUpdate(Snapshot: stateMachine.Snapshot));
        }
    }

    private void CancelPreparingGeneration(Guid generation)
    {
        lock (callbackGate)
        {
            if (stateMachine.Snapshot.Generation == generation
                && stateMachine.Snapshot.Phase == DictationPhase.Preparing)
            {
                stateMachine.Cancel();
                PublishSafely(new DictationProgressUpdate(Snapshot: stateMachine.Snapshot));
            }
        }
    }

    private void FailPreparingGeneration(RunContext context)
    {
        FailPreparingGeneration(
            context,
            new VoxFlowError(VoxFlowErrorCode.Unknown));
    }

    private void FailPreparingGeneration(
        RunContext context,
        VoxFlowError error)
    {
        lock (callbackGate)
        {
            if (ReferenceEquals(activeContext, context))
            {
                activeContext = null;
            }

            FailPreparingGenerationUnsafe(context.Generation, error);
        }
    }

    private void FailPreparingGeneration(Guid generation)
    {
        lock (callbackGate)
        {
            FailPreparingGenerationUnsafe(
                generation,
                new VoxFlowError(VoxFlowErrorCode.Unknown));
        }
    }

    private void FailPreparingGenerationUnsafe(
        Guid generation,
        VoxFlowError error)
    {
        if (stateMachine.TryFail(generation, error))
        {
            PublishSafely(new DictationProgressUpdate(stateMachine.Snapshot));
        }
    }

    private async Task CancelAndDisposeContextAsync(RunContext context)
    {
        context.Cancel();
        await StopAudioOnceAsync(context).ConfigureAwait(false);
        await CancelSessionOnceAsync(context).ConfigureAwait(false);
        await CleanupContextAsync(context).ConfigureAwait(false);
        context.Completion.TrySetResult();
    }

    private async ValueTask StopAudioOnceAsync(RunContext context)
    {
        if (!context.AudioStartAttempted)
        {
            return;
        }

        _ = await context.AudioStartCompleted.Task.ConfigureAwait(false);

        if (!context.TryMarkAudioStopped())
        {
            await context.AudioStopCompleted.Task.ConfigureAwait(false);
            return;
        }

        try
        {
            await audio.StopAsync(CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception)
        {
            // Cleanup remains best effort; the visible operation state owns
            // any user-facing error classification.
        }
        finally
        {
            context.AudioStopCompleted.TrySetResult();
        }
    }

    private static async ValueTask CancelSessionOnceAsync(RunContext context)
    {
        if (!context.TryMarkSessionCancelled())
        {
            return;
        }

        try
        {
            await context.Session.CancelAsync(CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception)
        {
            // Session disposal is still required after a failed cancel.
        }
    }

    private async Task CleanupContextAsync(RunContext context)
    {
        if (!context.TryBeginCleanup())
        {
            await context.CleanupCompleted.Task.ConfigureAwait(false);
            return;
        }

        try
        {
            context.Cancel();
            context.Unsubscribe();
            await DisposeSessionSafelyAsync(context.Session).ConfigureAwait(false);
            context.DisposeCancellation();
        }
        finally
        {
            contexts.TryRemove(context.Generation, out _);
            context.CleanupCompleted.TrySetResult();
        }
    }

    private static async ValueTask DisposeSessionSafelyAsync(
        IDictationAsrSession session)
    {
        try
        {
            await session.DisposeAsync().ConfigureAwait(false);
        }
        catch (Exception)
        {
            // Dispose must not replace an already-delivered dictation result.
        }
    }

    private async ValueTask SaveHistorySafelyAsync(
        RunContext context,
        string rawText,
        string finalText,
        OutputResult outputResult)
    {
        try
        {
            await history.SaveAsync(
                    new DictationHistoryDraft(
                        context.Generation,
                        rawText,
                        finalText,
                        outputResult,
                        timeProvider.GetUtcNow()),
                    CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception)
        {
            // Text has already been delivered. History persistence is
            // intentionally non-destructive to that completed result.
        }
    }

    private bool IsCurrentContext(RunContext context)
    {
        lock (callbackGate)
        {
            return ReferenceEquals(activeContext, context)
                && stateMachine.Snapshot.Generation == context.Generation
                && stateMachine.Snapshot.Phase is
                    DictationPhase.Preparing or
                    DictationPhase.Recording or
                    DictationPhase.WaitingForFinal;
        }
    }

    private void PublishSafely(DictationProgressUpdate update)
    {
        try
        {
            progress.Publish(update);
        }
        catch (Exception)
        {
            // A presentation projection cannot break the dictation pipeline.
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
    }

    private sealed class ProcessingProgress(
        DictationOrchestrator owner,
        RunContext context) : IProgress<string>
    {
        public void Report(string value) => owner.PublishProcessingProgress(context, value);
    }

    private sealed record ProviderTerminal(string? FinalText, VoxFlowError? Error)
    {
        public static ProviderTerminal FromFinal(string text) => new(text, null);

        public static ProviderTerminal FromError(VoxFlowError error) => new(null, error);
    }

    private sealed class RunContext
    {
        private readonly OrderedAudioForwarder audioForwarder;
        private int audioStartAttempted;
        private int audioStopped;
        private int finishStarted;
        private int outputCommitStarted;
        private int sessionCancelled;
        private int stopStarted;
        private int stopRequestedDuringPreparation;
        private int cleanupStarted;
        private long lastPartialRevision = -1;

        public RunContext(
            DictationOrchestrator owner,
            Guid generation,
            IDictationAsrSession session,
            TimeProvider timeProvider,
            CancellationTokenSource? cancellation = null)
        {
            Generation = generation;
            Session = session;
            Cancellation = cancellation ?? new CancellationTokenSource();
            Token = Cancellation.Token;
            audioForwarder = new OrderedAudioForwarder(
                (frame, frameCancellation) =>
                    owner.PushAudioAsync(this, frame, frameCancellation),
                exception => owner.OnAudioForwardingFailure(this, exception),
                timeProvider,
                Terminal.Task,
                Token);
            PartialHandler = (_, result) => owner.OnPartial(this, result);
            FinalHandler = (_, result) => owner.OnFinal(this, result);
            FailureHandler = (_, error) => owner.OnProviderFailure(this, error);
        }

        public Guid Generation { get; }

        public IDictationAsrSession Session { get; }

        public CancellationTokenSource Cancellation { get; }

        public CancellationToken Token { get; }

        public TaskCompletionSource<ProviderTerminal> Terminal { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource Completion { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource CleanupCompleted { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<bool> AudioStartCompleted { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource AudioStopCompleted { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public EventHandler<AsrPartialResult> PartialHandler { get; }

        public EventHandler<AsrFinalResult> FinalHandler { get; }

        public EventHandler<VoxFlowError> FailureHandler { get; }

        public bool AudioStartAttempted => Volatile.Read(ref audioStartAttempted) != 0;

        public bool StopStarted => Volatile.Read(ref stopStarted) != 0;

        public bool OutputCommitStarted => Volatile.Read(ref outputCommitStarted) != 0;

        public bool StopRequestedDuringPreparation =>
            Volatile.Read(ref stopRequestedDuringPreparation) != 0;

        public void Subscribe()
        {
            Session.PartialReceived += PartialHandler;
            Session.FinalReceived += FinalHandler;
            Session.Failed += FailureHandler;
        }

        public void Unsubscribe()
        {
            Session.PartialReceived -= PartialHandler;
            Session.FinalReceived -= FinalHandler;
            Session.Failed -= FailureHandler;
        }

        public void MarkAudioStartAttempted() =>
            Interlocked.Exchange(ref audioStartAttempted, 1);

        public void MarkAudioStartCompleted(bool started) =>
            AudioStartCompleted.TrySetResult(started);

        public ValueTask ForwardAudioAsync(
            ReadOnlyMemory<byte> frame,
            CancellationToken frameCancellation) =>
            audioForwarder.ForwardAsync(frame, frameCancellation);

        public void ActivateAudio() => audioForwarder.Activate();

        public Task DrainAudioAsync() => audioForwarder.DrainAsync();

        public bool TryMarkAudioStopped() =>
            Interlocked.CompareExchange(ref audioStopped, 1, 0) == 0;

        public bool TryMarkFinishStarted() =>
            Interlocked.CompareExchange(ref finishStarted, 1, 0) == 0;

        public void MarkOutputCommitStarted() =>
            Interlocked.Exchange(ref outputCommitStarted, 1);

        public bool TryMarkSessionCancelled() =>
            Interlocked.CompareExchange(ref sessionCancelled, 1, 0) == 0;

        public bool TryMarkStopStarted() =>
            Interlocked.CompareExchange(ref stopStarted, 1, 0) == 0;

        public void RequestStopDuringPreparation() =>
            Interlocked.Exchange(ref stopRequestedDuringPreparation, 1);

        public bool TryBeginCleanup() =>
            Interlocked.CompareExchange(ref cleanupStarted, 1, 0) == 0;

        public bool TryAdvancePartialRevision(long revision)
        {
            if (revision <= lastPartialRevision)
            {
                return false;
            }

            lastPartialRevision = revision;
            return true;
        }

        public void Cancel()
        {
            try
            {
                Cancellation.Cancel();
            }
            catch (ObjectDisposedException)
            {
                // Cleanup may race a redundant terminal coordinator.
            }
            finally
            {
                audioForwarder.Close();
            }
        }

        public void DisposeCancellation() => Cancellation.Dispose();
    }

    private sealed class OrderedAudioForwarder
    {
        private const int PcmBytesPerSecond = 16_000 * sizeof(short);
        private const int MaximumBufferedFrames = 3_000;
        private const int MaximumQueuedFrames = 6_000;

        // Keep the full utterance for the same bounded window allowed to the
        // provider handshake. Thirty seconds of PCM16 mono is under one MiB.
        private const int MaximumBufferedBytes = PcmBytesPerSecond * 30;
        private const int MaximumQueuedBytes = PcmBytesPerSecond * 60;
        private static readonly TimeSpan SendTimeout = TimeSpan.FromSeconds(10);
        private static readonly TimeSpan SendCancellationGrace = TimeSpan.FromSeconds(1);

        private readonly object gate = new();
        private readonly Queue<byte[]> bufferedFrames = new();
        private readonly Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> send;
        private readonly Action<Exception> reportFailure;
        private readonly TimeProvider timeProvider;
        private readonly Task terminalTask;
        private readonly CancellationToken cancellationToken;
        private Task sendTail = Task.CompletedTask;
        private ForwardingState state = ForwardingState.Buffering;
        private int bufferedByteCount;
        private int queuedByteCount;
        private int queuedFrameCount;
        private int failureReported;

        public OrderedAudioForwarder(
            Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> send,
            Action<Exception> reportFailure,
            TimeProvider timeProvider,
            Task terminalTask,
            CancellationToken cancellationToken)
        {
            this.send = send;
            this.reportFailure = reportFailure;
            this.timeProvider = timeProvider;
            this.terminalTask = terminalTask;
            this.cancellationToken = cancellationToken;
        }

        public ValueTask ForwardAsync(
            ReadOnlyMemory<byte> frame,
            CancellationToken frameCancellation)
        {
            if (frame.IsEmpty
                || frameCancellation.IsCancellationRequested
                || cancellationToken.IsCancellationRequested)
            {
                return ValueTask.CompletedTask;
            }

            // The capture backend owns its frame memory only until this callback
            // returns; both buffering and queued live sends need an owned copy.
            var ownedFrame = frame.ToArray();
            Exception? overflow = null;
            lock (gate)
            {
                if (state == ForwardingState.Closed)
                {
                    return ValueTask.CompletedTask;
                }

                if (state == ForwardingState.Buffering)
                {
                    BufferUnsafe(ownedFrame);
                    return ValueTask.CompletedTask;
                }

                // Capture must keep draining WASAPI while pre-roll is replayed
                // at real-time speed. The ordered background tail owns send
                // failures and StopAsync drains it before FinishAsync.
                if (!TryQueueSendUnsafe(ownedFrame))
                {
                    state = ForwardingState.Closed;
                    overflow = new InvalidOperationException(
                        "The ASR audio send queue exceeded its bounded capacity.");
                }
            }

            if (overflow is not null)
            {
                ReportFailureOnce(overflow);
            }
            return ValueTask.CompletedTask;
        }

        public void Activate()
        {
            Exception? overflow = null;
            lock (gate)
            {
                if (state == ForwardingState.Closed)
                {
                    return;
                }

                if (state == ForwardingState.Live)
                {
                    return;
                }

                while (bufferedFrames.TryDequeue(out var frame))
                {
                    if (!TryQueueSendUnsafe(frame))
                    {
                        overflow = new InvalidOperationException(
                            "The ASR audio send queue exceeded its bounded capacity.");
                        state = ForwardingState.Closed;
                        bufferedFrames.Clear();
                        break;
                    }
                }

                bufferedByteCount = 0;
                if (overflow is null)
                {
                    state = ForwardingState.Live;
                }
            }

            if (overflow is not null)
            {
                ReportFailureOnce(overflow);
            }
        }

        public Task DrainAsync()
        {
            lock (gate)
            {
                return sendTail;
            }
        }

        public void Close()
        {
            lock (gate)
            {
                state = ForwardingState.Closed;
                bufferedFrames.Clear();
                bufferedByteCount = 0;
            }
        }

        private void BufferUnsafe(byte[] frame)
        {
            if (frame.Length > MaximumBufferedBytes)
            {
                frame = frame[^MaximumBufferedBytes..];
            }

            while (bufferedFrames.Count > 0
                && (bufferedFrames.Count >= MaximumBufferedFrames
                    || bufferedByteCount + frame.Length > MaximumBufferedBytes))
            {
                bufferedByteCount -= bufferedFrames.Dequeue().Length;
            }

            bufferedFrames.Enqueue(frame);
            bufferedByteCount += frame.Length;
        }

        private bool TryQueueSendUnsafe(byte[] frame)
        {
            if (queuedFrameCount >= MaximumQueuedFrames
                || queuedByteCount + frame.Length > MaximumQueuedBytes)
            {
                return false;
            }

            queuedFrameCount++;
            queuedByteCount += frame.Length;
            sendTail = SendAfterAsync(sendTail, frame);
            return true;
        }

        private async Task SendAfterAsync(Task predecessor, byte[] frame)
        {
            try
            {
                // Never invoke provider code while the ordering lock is held.
                await Task.Yield();
                await predecessor.ConfigureAwait(false);
                if (terminalTask.IsCompleted)
                {
                    return;
                }

                cancellationToken.ThrowIfCancellationRequested();

                var sendStarted = timeProvider.GetTimestamp();
                using var sendCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken);
                using var timeoutDelayCancellation =
                    CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                var timeoutTask = Task.Delay(
                    SendTimeout,
                    timeProvider,
                    timeoutDelayCancellation.Token);
                var sendTask = send(frame, sendCancellation.Token).AsTask();
                var completed = await Task.WhenAny(
                        sendTask,
                        terminalTask,
                        timeoutTask)
                    .ConfigureAwait(false);
                CancelSafely(timeoutDelayCancellation);
                if (terminalTask.IsCompleted)
                {
                    CancelSafely(sendCancellation);
                    await AwaitSendCancellationAsync(sendTask).ConfigureAwait(false);
                    return;
                }

                if (!ReferenceEquals(completed, sendTask))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    CancelSafely(sendCancellation);
                    await AwaitSendCancellationAsync(sendTask).ConfigureAwait(false);
                    throw new TimeoutException(
                        "The selected ASR provider did not accept audio in time.");
                }

                await sendTask.ConfigureAwait(false);
                if (terminalTask.IsCompleted)
                {
                    return;
                }

                // Cloud streaming APIs consume PCM in real time. Space each
                // send by its 16 kHz mono duration so pre-roll cannot be burst
                // into Tencent/Aliyun/Volcengine faster than 1:1.
                var audioDuration = TimeSpan.FromSeconds(
                    frame.Length / (double)PcmBytesPerSecond);
                var sendElapsed = timeProvider.GetElapsedTime(sendStarted);
                var remaining = audioDuration - sendElapsed;
                if (remaining > TimeSpan.Zero)
                {
                    using var pacingCancellation =
                        CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    var pacingTask = Task.Delay(
                        remaining,
                        timeProvider,
                        pacingCancellation.Token);
                    var pacingCompleted = await Task.WhenAny(pacingTask, terminalTask)
                        .ConfigureAwait(false);
                    if (ReferenceEquals(pacingCompleted, pacingTask))
                    {
                        await pacingTask.ConfigureAwait(false);
                    }
                    else
                    {
                        CancelSafely(pacingCancellation);
                    }
                }
            }
            catch (Exception) when (terminalTask.IsCompleted)
            {
                // An authoritative terminal result wins over queued replay and
                // collapses the remaining pacing tail immediately.
            }
            catch (OperationCanceledException) when (
                cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                ReportFailureOnce(exception);
                throw;
            }
            finally
            {
                lock (gate)
                {
                    queuedFrameCount--;
                    queuedByteCount -= frame.Length;
                }
            }
        }

        private void ReportFailureOnce(Exception exception)
        {
            if (Interlocked.CompareExchange(ref failureReported, 1, 0) == 0)
            {
                reportFailure(exception);
            }
        }

        private static void CancelSafely(CancellationTokenSource cancellation)
        {
            try
            {
                cancellation.Cancel();
            }
            catch (ObjectDisposedException)
            {
                // A completed send may dispose its linked timeout concurrently.
            }
        }

        private static void ObserveFault(Task task)
        {
            _ = task.ContinueWith(
                static completed => _ = completed.Exception,
                CancellationToken.None,
                TaskContinuationOptions.OnlyOnFaulted
                    | TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private async Task AwaitSendCancellationAsync(Task sendTask)
        {
            try
            {
                await sendTask.WaitAsync(
                        SendCancellationGrace,
                        timeProvider,
                        CancellationToken.None)
                    .ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                ObserveFault(sendTask);
            }
            catch (Exception)
            {
                // The terminal result or explicit timeout already owns the
                // visible outcome; cancellation cleanup is best effort.
            }
        }

        private enum ForwardingState
        {
            Buffering,
            Live,
            Closed,
        }
    }

    private sealed class StartReservation
    {
        private CancellationTokenSource? cancellation;

        public StartReservation(Guid generation, CancellationToken callerToken)
        {
            Generation = generation;
            cancellation = CancellationTokenSource.CreateLinkedTokenSource(callerToken);
            Token = cancellation.Token;
        }

        public Guid Generation { get; }

        public CancellationToken Token { get; }

        public CancellationTokenSource TakeCancellation() =>
            Interlocked.Exchange(ref cancellation, null)
            ?? throw new InvalidOperationException(
                "The start reservation cancellation source was already claimed.");

        public void Cancel()
        {
            try
            {
                Volatile.Read(ref cancellation)?.Cancel();
            }
            catch (ObjectDisposedException)
            {
                // Preparation cleanup may race a redundant cancellation.
            }
        }

        public void DisposeIfUnclaimed() =>
            Interlocked.Exchange(ref cancellation, null)?.Dispose();
    }
}
