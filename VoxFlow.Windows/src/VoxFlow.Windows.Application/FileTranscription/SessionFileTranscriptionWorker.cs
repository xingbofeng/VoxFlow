using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public interface IFileTranscriptionPcmFrameSource
{
    IAsyncEnumerable<ReadOnlyMemory<byte>> ReadFramesAsync(
        string audioPath,
        CancellationToken cancellationToken);
}

public interface IFileTranscriptionProviderErrorException
{
    VoxFlowError Error { get; }
}

public interface IFileTranscriptionSessionFactory
{
    ValueTask<IDictationAsrSession> CreateSessionAsync(
        AsrProviderId provider,
        RecognitionLanguage language,
        Guid generation,
        CancellationToken cancellationToken);
}

public interface IFileTranscriptionProviderSessionAdapter
{
    AsrProviderId Provider { get; }

    ValueTask<IDictationAsrSession> CreateSessionAsync(
        RecognitionLanguage language,
        Guid generation,
        CancellationToken cancellationToken);
}

public sealed class DictationProviderFileTranscriptionAdapter
    : IFileTranscriptionProviderSessionAdapter
{
    private readonly Func<RecognitionLanguage, IDictationAsrProvider> providerFactory;

    public DictationProviderFileTranscriptionAdapter(
        AsrProviderId provider,
        Func<RecognitionLanguage, IDictationAsrProvider> providerFactory)
    {
        if (!Enum.IsDefined(provider))
        {
            throw new ArgumentOutOfRangeException(nameof(provider));
        }

        Provider = provider;
        this.providerFactory = providerFactory
            ?? throw new ArgumentNullException(nameof(providerFactory));
    }

    public AsrProviderId Provider { get; }

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        RecognitionLanguage language,
        Guid generation,
        CancellationToken cancellationToken)
    {
        var provider = providerFactory(language)
            ?? throw new FileTranscriptionProviderUnavailableException(Provider);
        if (provider.Availability != AsrProviderAvailability.Ready)
        {
            throw new FileTranscriptionProviderUnavailableException(
                Provider,
                Provider == AsrProviderId.Qwen
                    ? FileTranscriptionErrorCode.ProviderModelNotReady
                    : FileTranscriptionErrorCode.ProviderUnavailable);
        }

        return provider.CreateSessionAsync(generation, cancellationToken);
    }
}

public sealed class FileTranscriptionProviderUnavailableException(
    AsrProviderId provider,
    FileTranscriptionErrorCode errorCode = FileTranscriptionErrorCode.ProviderUnavailable)
    : Exception($"The recorded file-transcription provider is unavailable ({provider}).")
{
    public AsrProviderId Provider { get; } = provider;

    public FileTranscriptionErrorCode ErrorCode { get; } = errorCode;
}

public sealed class FileTranscriptionSessionFactory : IFileTranscriptionSessionFactory
{
    private readonly IReadOnlyDictionary<AsrProviderId, IFileTranscriptionProviderSessionAdapter>
        adapters;

    public FileTranscriptionSessionFactory(
        IEnumerable<IFileTranscriptionProviderSessionAdapter> adapters)
    {
        ArgumentNullException.ThrowIfNull(adapters);
        var byProvider = new Dictionary<AsrProviderId, IFileTranscriptionProviderSessionAdapter>();
        foreach (var adapter in adapters)
        {
            ArgumentNullException.ThrowIfNull(adapter);
            if (!byProvider.TryAdd(adapter.Provider, adapter))
            {
                throw new ArgumentException(
                    $"Duplicate file-transcription adapter for {adapter.Provider}.",
                    nameof(adapters));
            }
        }

        this.adapters = byProvider;
    }

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        AsrProviderId provider,
        RecognitionLanguage language,
        Guid generation,
        CancellationToken cancellationToken)
    {
        if (!adapters.TryGetValue(provider, out var adapter))
        {
            throw new FileTranscriptionProviderUnavailableException(provider);
        }

        return adapter.CreateSessionAsync(language, generation, cancellationToken);
    }
}

public sealed class SessionFileTranscriptionWorker : IFileTranscriptionWorker
{
    private readonly IFileTranscriptionSessionFactory sessionFactory;
    private readonly IFileTranscriptionPcmFrameSource pcmFrameSource;
    private readonly TimeSpan finalResultTimeout;

    public SessionFileTranscriptionWorker(
        IFileTranscriptionSessionFactory sessionFactory,
        IFileTranscriptionPcmFrameSource pcmFrameSource,
        TimeSpan finalResultTimeout)
    {
        this.sessionFactory = sessionFactory
            ?? throw new ArgumentNullException(nameof(sessionFactory));
        this.pcmFrameSource = pcmFrameSource
            ?? throw new ArgumentNullException(nameof(pcmFrameSource));
        if (finalResultTimeout <= TimeSpan.Zero
            || finalResultTimeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(finalResultTimeout));
        }

        this.finalResultTimeout = finalResultTimeout;
    }

    public async ValueTask<FileTranscriptionWorkerResult> TranscribeAsync(
        FileTranscriptionSegmentRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        var completion = new TaskCompletionSource<FileTranscriptionWorkerResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);

        IDictationAsrSession session;
        try
        {
            session = await sessionFactory.CreateSessionAsync(
                request.Provider,
                request.Language,
                Guid.NewGuid(),
                cancellationToken).ConfigureAwait(false);
        }
        catch (FileTranscriptionProviderUnavailableException exception)
        {
            return new FileTranscriptionWorkerResult(null, exception.ErrorCode);
        }
        await using var ownedSession = session;

        void OnFinal(object? _, AsrFinalResult result) =>
            completion.TrySetResult(new FileTranscriptionWorkerResult(result.Text));
        void OnFailed(object? _, VoxFlowError error) =>
            completion.TrySetResult(new FileTranscriptionWorkerResult(
                null,
                MapProviderError(error.Code)));

        session.FinalReceived += OnFinal;
        session.Failed += OnFailed;
        try
        {
            await session.StartAsync(cancellationToken).ConfigureAwait(false);
            await foreach (var frame in pcmFrameSource.ReadFramesAsync(
                request.AudioPath,
                cancellationToken).WithCancellation(cancellationToken).ConfigureAwait(false))
            {
                if (!frame.IsEmpty)
                {
                    await session.PushAudioAsync(frame, cancellationToken).ConfigureAwait(false);
                }
            }

            await session.FinishAsync(cancellationToken).ConfigureAwait(false);
            return await completion.Task
                .WaitAsync(finalResultTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await CancelBestEffortAsync(session).ConfigureAwait(false);
            throw;
        }
        catch (TimeoutException)
        {
            await CancelBestEffortAsync(session).ConfigureAwait(false);
            return new FileTranscriptionWorkerResult(
                null,
                FileTranscriptionErrorCode.SegmentTimedOut);
        }
        catch (Exception exception)
            when (exception is IFileTranscriptionProviderErrorException providerError)
        {
            await CancelBestEffortAsync(session).ConfigureAwait(false);
            return new FileTranscriptionWorkerResult(
                null,
                MapProviderError(providerError.Error.Code));
        }
        finally
        {
            session.FinalReceived -= OnFinal;
            session.Failed -= OnFailed;
        }
    }

    private static FileTranscriptionErrorCode MapProviderError(
        VoxFlowErrorCode errorCode) => errorCode switch
        {
            VoxFlowErrorCode.AuthenticationFailed =>
                FileTranscriptionErrorCode.ProviderAuthenticationFailed,
            VoxFlowErrorCode.QuotaExceeded =>
                FileTranscriptionErrorCode.ProviderQuotaExceeded,
            VoxFlowErrorCode.AudioFormatInvalid =>
                FileTranscriptionErrorCode.ProviderAudioFormatInvalid,
            VoxFlowErrorCode.ModelNotReady =>
                FileTranscriptionErrorCode.ProviderModelNotReady,
            VoxFlowErrorCode.NetworkFailure =>
                FileTranscriptionErrorCode.ProviderNetworkFailure,
            VoxFlowErrorCode.FinalTimeout =>
                FileTranscriptionErrorCode.SegmentTimedOut,
            _ => FileTranscriptionErrorCode.ProviderFailure,
        };

    private static async ValueTask CancelBestEffortAsync(IDictationAsrSession session)
    {
        try
        {
            await session.CancelAsync(CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // The original provider failure is more useful than a secondary
            // cancellation failure and remains safe to persist.
        }
    }
}
