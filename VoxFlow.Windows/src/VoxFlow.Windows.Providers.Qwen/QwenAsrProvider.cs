using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Qwen;

internal interface IQwenProviderReadiness
{
    bool IsReadyFor(QwenVariant variant);
}

internal interface IQwenSessionAttemptFactory
{
    ValueTask PrewarmAsync(
        QwenVariant variant,
        CancellationToken cancellationToken);

    ValueTask<IDictationAsrSession> CreateAsync(
        QwenVariant variant,
        Guid generation,
        CancellationToken cancellationToken);
}

internal sealed class QwenAsrProvider : IDictationAsrProvider
{
    private readonly QwenVariant variant;
    private readonly IQwenProviderReadiness readiness;
    private readonly IQwenSessionAttemptFactory attemptFactory;

    internal QwenAsrProvider(
        QwenVariant variant,
        IQwenProviderReadiness readiness,
        IQwenSessionAttemptFactory attemptFactory)
    {
        this.variant = variant;
        this.readiness = readiness ?? throw new ArgumentNullException(nameof(readiness));
        this.attemptFactory = attemptFactory ?? throw new ArgumentNullException(nameof(attemptFactory));
    }

    public AsrProviderAvailability Availability => readiness.IsReadyFor(variant)
        ? AsrProviderAvailability.Ready
        : AsrProviderAvailability.NotReady;

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!readiness.IsReadyFor(variant))
        {
            throw new InvalidOperationException("The selected Qwen model is not ready.");
        }

        return ValueTask.FromResult<IDictationAsrSession>(
            new QwenSupervisedDictationSession(
                variant,
                generation,
                attemptFactory));
    }
}

internal sealed class QwenSupervisedDictationSession : IDictationAsrSession
{
    private readonly QwenVariant variant;
    private readonly Guid generation;
    private readonly IQwenSessionAttemptFactory attemptFactory;
    private readonly SemaphoreSlim operationGate = new(1, 1);
    private readonly object stateLock = new();
    private readonly List<byte[]> audioFrames = [];
    private AttemptBinding? current;
    private Task? retryTask;
    private int attemptVersion;
    private int retries;
    private long lastNativeRevision = -1;
    private long publishedRevision;
    private string? lastPartial;
    private bool started;
    private bool finishRequested;
    private bool cancelled;
    private bool finalPublished;
    private bool failurePublished;
    private bool retryScheduled;
    private bool disposed;

    internal QwenSupervisedDictationSession(
        QwenVariant variant,
        Guid generation,
        IQwenSessionAttemptFactory attemptFactory)
    {
        this.variant = variant;
        this.generation = generation;
        this.attemptFactory = attemptFactory ?? throw new ArgumentNullException(nameof(attemptFactory));
    }

    public event EventHandler<AsrPartialResult>? PartialReceived;

    public event EventHandler<AsrFinalResult>? FinalReceived;

    public event EventHandler<VoxFlowError>? Failed;

    public async ValueTask StartAsync(CancellationToken cancellationToken)
    {
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (stateLock)
            {
                ThrowIfUnavailable();
                if (started)
                {
                    throw new InvalidOperationException("The Qwen session has already started.");
                }

                started = true;
            }

            IDictationAsrSession attempt = await attemptFactory
                .CreateAsync(variant, generation, cancellationToken)
                .ConfigureAwait(false);
            AttemptBinding binding = Bind(attempt);
            lock (stateLock)
            {
                current = binding;
            }

            await attempt.StartAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            operationGate.Release();
        }
    }

    public async ValueTask PushAudioAsync(
        ReadOnlyMemory<byte> pcmS16LittleEndian,
        CancellationToken cancellationToken)
    {
        byte[] copy = pcmS16LittleEndian.ToArray();
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            AttemptBinding binding;
            lock (stateLock)
            {
                ThrowIfUnavailable();
                binding = current ?? throw new InvalidOperationException("The Qwen session has not started.");
                audioFrames.Add(copy);
            }

            await binding.Attempt.PushAudioAsync(copy, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            operationGate.Release();
        }
    }

    public async ValueTask FinishAsync(CancellationToken cancellationToken)
    {
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            AttemptBinding binding;
            lock (stateLock)
            {
                ThrowIfUnavailable();
                finishRequested = true;
                binding = current ?? throw new InvalidOperationException("The Qwen session has not started.");
            }

            await binding.Attempt.FinishAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            operationGate.Release();
        }
    }

    public async ValueTask CancelAsync(CancellationToken cancellationToken)
    {
        await operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            AttemptBinding? binding;
            lock (stateLock)
            {
                if (cancelled)
                {
                    return;
                }

                cancelled = true;
                attemptVersion++;
                binding = current;
            }

            if (binding is not null)
            {
                await binding.Attempt.CancelAsync(cancellationToken).ConfigureAwait(false);
            }
        }
        finally
        {
            operationGate.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        bool shouldCancel;
        lock (stateLock)
        {
            if (disposed)
            {
                return;
            }

            shouldCancel = !cancelled;
        }

        if (shouldCancel)
        {
            await CancelAsync(CancellationToken.None).ConfigureAwait(false);
        }

        Task? pendingRetry;
        lock (stateLock)
        {
            pendingRetry = retryTask;
        }

        if (pendingRetry is not null)
        {
            await pendingRetry.ConfigureAwait(false);
        }

        await operationGate.WaitAsync().ConfigureAwait(false);
        try
        {
            AttemptBinding? binding;
            lock (stateLock)
            {
                disposed = true;
                binding = current;
                current = null;
            }

            if (binding is not null)
            {
                Unbind(binding);
                await binding.Attempt.DisposeAsync().ConfigureAwait(false);
            }
        }
        finally
        {
            operationGate.Release();
            operationGate.Dispose();
        }
    }

    private AttemptBinding Bind(IDictationAsrSession attempt)
    {
        int version = ++attemptVersion;
        EventHandler<AsrPartialResult> partial = (_, value) => HandlePartial(version, value);
        EventHandler<AsrFinalResult> final = (_, value) => HandleFinal(version, value);
        EventHandler<VoxFlowError> failed = (_, value) => HandleFailure(version, value);
        attempt.PartialReceived += partial;
        attempt.FinalReceived += final;
        attempt.Failed += failed;
        return new AttemptBinding(attempt, version, partial, final, failed);
    }

    private static void Unbind(AttemptBinding binding)
    {
        binding.Attempt.PartialReceived -= binding.Partial;
        binding.Attempt.FinalReceived -= binding.Final;
        binding.Attempt.Failed -= binding.Failed;
    }

    private void HandlePartial(int version, AsrPartialResult value)
    {
        AsrPartialResult? published = null;
        lock (stateLock)
        {
            if (!CanPublish(version) || value.Revision <= lastNativeRevision || StringComparer.Ordinal.Equals(lastPartial, value.Text))
            {
                return;
            }

            lastNativeRevision = value.Revision;
            lastPartial = value.Text;
            published = new AsrPartialResult(value.Text, ++publishedRevision);
        }

        PartialReceived?.Invoke(this, published);
    }

    private void HandleFinal(int version, AsrFinalResult value)
    {
        if (string.IsNullOrWhiteSpace(value.Text))
        {
            PublishFailure(
                version,
                new VoxFlowError(VoxFlowErrorCode.EmptyFinal, AsrProviderId.Qwen));
            return;
        }

        lock (stateLock)
        {
            if (!CanPublish(version))
            {
                return;
            }

            finalPublished = true;
        }

        FinalReceived?.Invoke(this, value);
    }

    private void HandleFailure(int version, VoxFlowError error)
    {
        bool shouldRetry = false;
        lock (stateLock)
        {
            if (!CanPublish(version))
            {
                return;
            }

            if (error.Code == VoxFlowErrorCode.NativeRuntimeFailure && retries == 0 && !retryScheduled)
            {
                retryScheduled = true;
                retries = 1;
                shouldRetry = true;
            }
        }

        if (shouldRetry)
        {
            Task task = Task.Run(() => RetryAsync(version), CancellationToken.None);
            lock (stateLock)
            {
                retryTask = task;
            }

            return;
        }

        PublishFailure(version, error);
    }

    private async Task RetryAsync(int failedVersion)
    {
        await operationGate.WaitAsync().ConfigureAwait(false);
        try
        {
            AttemptBinding oldBinding;
            byte[][] frames;
            bool shouldFinish;
            lock (stateLock)
            {
                if (cancelled || disposed || finalPublished || failurePublished || current?.Version != failedVersion)
                {
                    return;
                }

                oldBinding = current;
                current = null;
                attemptVersion++;
                frames = audioFrames.Select(frame => frame.ToArray()).ToArray();
                shouldFinish = finishRequested;
            }

            Unbind(oldBinding);
            await oldBinding.Attempt.DisposeAsync().ConfigureAwait(false);
            await attemptFactory.PrewarmAsync(variant, CancellationToken.None).ConfigureAwait(false);
            IDictationAsrSession next = await attemptFactory
                .CreateAsync(variant, generation, CancellationToken.None)
                .ConfigureAwait(false);
            AttemptBinding nextBinding = Bind(next);
            lock (stateLock)
            {
                if (cancelled || disposed)
                {
                    Unbind(nextBinding);
                }
                else
                {
                    current = nextBinding;
                    lastNativeRevision = -1;
                    retryScheduled = false;
                }
            }

            if (current != nextBinding)
            {
                await next.DisposeAsync().ConfigureAwait(false);
                return;
            }

            await next.StartAsync(CancellationToken.None).ConfigureAwait(false);
            foreach (byte[] frame in frames)
            {
                await next.PushAudioAsync(frame, CancellationToken.None).ConfigureAwait(false);
            }

            if (shouldFinish)
            {
                await next.FinishAsync(CancellationToken.None).ConfigureAwait(false);
            }
        }
        catch
        {
            PublishFailure(
                null,
                new VoxFlowError(
                    VoxFlowErrorCode.NativeRuntimeFailure,
                    AsrProviderId.Qwen));
        }
        finally
        {
            operationGate.Release();
        }
    }

    private void PublishFailure(int? version, VoxFlowError error)
    {
        lock (stateLock)
        {
            if (cancelled || disposed || finalPublished || failurePublished || (version is not null && current?.Version != version))
            {
                return;
            }

            failurePublished = true;
        }

        Failed?.Invoke(this, error);
    }

    private bool CanPublish(int version) =>
        !cancelled &&
        !disposed &&
        !finalPublished &&
        !failurePublished &&
        current?.Version == version;

    private void ThrowIfUnavailable()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (cancelled)
        {
            throw new OperationCanceledException("The Qwen session was cancelled.");
        }
    }

    private sealed record AttemptBinding(
        IDictationAsrSession Attempt,
        int Version,
        EventHandler<AsrPartialResult> Partial,
        EventHandler<AsrFinalResult> Final,
        EventHandler<VoxFlowError> Failed);
}
