using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionSessionWorkerTests
{
    [Theory]
    [InlineData(AsrProviderId.Qwen, RecognitionLanguage.Automatic)]
    [InlineData(AsrProviderId.TencentCloud, RecognitionLanguage.ChineseMandarin)]
    [InlineData(AsrProviderId.AliyunDashScope, RecognitionLanguage.English)]
    [InlineData(AsrProviderId.Volcengine, RecognitionLanguage.Japanese)]
    public async Task Worker_uses_the_recorded_provider_and_language_and_finishes_the_session(
        AsrProviderId provider,
        RecognitionLanguage language)
    {
        var session = new FakeSession("final text");
        var factory = new CapturingSessionFactory(session);
        var pcm = new FixedWavePcmFrameSource();
        var worker = new SessionFileTranscriptionWorker(factory, pcm, TimeSpan.FromSeconds(1));

        var result = await worker.TranscribeAsync(
            Request(provider, language),
            CancellationToken.None);

        Assert.Equal("final text", result.Text);
        Assert.Null(result.ErrorCode);
        Assert.Equal([(provider, language)], factory.Requests);
        Assert.True(session.Started);
        Assert.True(session.Finished);
        Assert.False(session.Cancelled);
        Assert.NotEmpty(session.Frames);
        Assert.All(session.Frames, frame => Assert.True(frame.Length > 0));
    }

    [Theory]
    [InlineData(AsrProviderId.Qwen)]
    [InlineData(AsrProviderId.TencentCloud)]
    [InlineData(AsrProviderId.AliyunDashScope)]
    [InlineData(AsrProviderId.Volcengine)]
    public async Task Every_provider_cancels_the_session_when_the_file_operation_is_cancelled(
        AsrProviderId provider)
    {
        var session = new FakeSession(finalText: null);
        var worker = new SessionFileTranscriptionWorker(
            new CapturingSessionFactory(session),
            new BlockingPcmFrameSource(),
            TimeSpan.FromSeconds(1));
        using var cancellation = new CancellationTokenSource();

        var task = worker.TranscribeAsync(
            Request(provider, RecognitionLanguage.Automatic),
            cancellation.Token).AsTask();
        await session.StartedSignal.Task.WaitAsync(TimeSpan.FromSeconds(1));
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => task);
        Assert.True(session.Cancelled);
        Assert.False(session.Finished);
    }

    [Fact]
    public async Task Registry_factory_never_falls_back_to_another_provider()
    {
        var qwen = new CapturingProviderSessionAdapter(AsrProviderId.Qwen);
        var factory = new FileTranscriptionSessionFactory([qwen]);

        await Assert.ThrowsAsync<FileTranscriptionProviderUnavailableException>(async () =>
            await factory.CreateSessionAsync(
                AsrProviderId.TencentCloud,
                RecognitionLanguage.English,
                Guid.NewGuid(),
                CancellationToken.None));

        Assert.Empty(qwen.RequestedLanguages);
    }

    [Theory]
    [InlineData(AsrProviderId.Qwen, RecognitionLanguage.Automatic)]
    [InlineData(AsrProviderId.TencentCloud, RecognitionLanguage.ChineseMandarin)]
    [InlineData(AsrProviderId.AliyunDashScope, RecognitionLanguage.English)]
    [InlineData(AsrProviderId.Volcengine, RecognitionLanguage.Korean)]
    public async Task Dictation_provider_adapter_reuses_the_existing_session_contract(
        AsrProviderId providerId,
        RecognitionLanguage language)
    {
        var session = new FakeSession("done");
        var provider = new FakeProvider(session);
        var languages = new List<RecognitionLanguage>();
        var adapter = new DictationProviderFileTranscriptionAdapter(
            providerId,
            recordedLanguage =>
            {
                languages.Add(recordedLanguage);
                return provider;
            });
        var generation = Guid.NewGuid();

        var restored = await adapter.CreateSessionAsync(
            language,
            generation,
            CancellationToken.None);

        Assert.Same(session, restored);
        Assert.Equal([language], languages);
        Assert.Equal([generation], provider.Generations);
    }

    [Theory]
    [InlineData(VoxFlowErrorCode.AuthenticationFailed, FileTranscriptionErrorCode.ProviderAuthenticationFailed)]
    [InlineData(VoxFlowErrorCode.QuotaExceeded, FileTranscriptionErrorCode.ProviderQuotaExceeded)]
    [InlineData(VoxFlowErrorCode.AudioFormatInvalid, FileTranscriptionErrorCode.ProviderAudioFormatInvalid)]
    [InlineData(VoxFlowErrorCode.ModelNotReady, FileTranscriptionErrorCode.ProviderModelNotReady)]
    [InlineData(VoxFlowErrorCode.NetworkFailure, FileTranscriptionErrorCode.ProviderNetworkFailure)]
    [InlineData(VoxFlowErrorCode.ProviderFailure, FileTranscriptionErrorCode.ProviderFailure)]
    public async Task Worker_preserves_readable_provider_error_categories(
        VoxFlowErrorCode sourceError,
        FileTranscriptionErrorCode expected)
    {
        var session = new FakeSession(finalText: null, failure: new VoxFlowError(sourceError));
        var worker = new SessionFileTranscriptionWorker(
            new CapturingSessionFactory(session),
            new FakePcmFrameSource([new byte[] { 0, 0 }]),
            TimeSpan.FromSeconds(1));

        var result = await worker.TranscribeAsync(
            Request(AsrProviderId.TencentCloud, RecognitionLanguage.English),
            CancellationToken.None);

        Assert.Equal(expected, result.ErrorCode);
    }

    [Theory]
    [InlineData(AsrProviderId.Qwen)]
    [InlineData(AsrProviderId.TencentCloud)]
    [InlineData(AsrProviderId.AliyunDashScope)]
    [InlineData(AsrProviderId.Volcengine)]
    public async Task Every_missing_recorded_provider_fails_without_fallback(
        AsrProviderId provider)
    {
        var worker = new SessionFileTranscriptionWorker(
            new FileTranscriptionSessionFactory([]),
            new FakePcmFrameSource([]),
            TimeSpan.FromSeconds(1));

        var result = await worker.TranscribeAsync(
            Request(provider, RecognitionLanguage.Automatic),
            CancellationToken.None);

        Assert.Equal(FileTranscriptionErrorCode.ProviderUnavailable, result.ErrorCode);
    }

    [Theory]
    [InlineData(AsrProviderId.Qwen)]
    [InlineData(AsrProviderId.TencentCloud)]
    [InlineData(AsrProviderId.AliyunDashScope)]
    [InlineData(AsrProviderId.Volcengine)]
    public async Task Every_provider_timeout_is_mapped_and_cancels_the_session(
        AsrProviderId provider)
    {
        var session = new FakeSession(finalText: null);
        var worker = new SessionFileTranscriptionWorker(
            new CapturingSessionFactory(session),
            new FakePcmFrameSource([]),
            TimeSpan.FromMilliseconds(10));

        var result = await worker.TranscribeAsync(
            Request(provider, RecognitionLanguage.Automatic),
            CancellationToken.None);

        Assert.Equal(FileTranscriptionErrorCode.SegmentTimedOut, result.ErrorCode);
        Assert.True(session.Cancelled);
    }

    [Fact]
    public async Task Worker_maps_provider_exception_raised_before_events_are_available()
    {
        var session = new FakeSession(
            finalText: null,
            startError: new FakeProviderException(
                new VoxFlowError(VoxFlowErrorCode.AuthenticationFailed)));
        var worker = new SessionFileTranscriptionWorker(
            new CapturingSessionFactory(session),
            new FakePcmFrameSource([]),
            TimeSpan.FromSeconds(1));

        var result = await worker.TranscribeAsync(
            Request(AsrProviderId.TencentCloud, RecognitionLanguage.English),
            CancellationToken.None);

        Assert.Equal(FileTranscriptionErrorCode.ProviderAuthenticationFailed, result.ErrorCode);
        Assert.True(session.Cancelled);
    }

    [Theory]
    [InlineData(AsrProviderId.Qwen, AsrProviderAvailability.NotReady, FileTranscriptionErrorCode.ProviderModelNotReady)]
    [InlineData(AsrProviderId.TencentCloud, AsrProviderAvailability.Unconfigured, FileTranscriptionErrorCode.ProviderUnavailable)]
    public async Task Adapter_maps_provider_availability_without_switching_provider(
        AsrProviderId providerId,
        AsrProviderAvailability availability,
        FileTranscriptionErrorCode expected)
    {
        var adapter = new DictationProviderFileTranscriptionAdapter(
            providerId,
            _ => new FakeProvider(new FakeSession("unused"), availability));
        var factory = new FileTranscriptionSessionFactory([adapter]);
        var worker = new SessionFileTranscriptionWorker(
            factory,
            new FakePcmFrameSource([]),
            TimeSpan.FromSeconds(1));

        var result = await worker.TranscribeAsync(
            Request(providerId, RecognitionLanguage.Automatic),
            CancellationToken.None);

        Assert.Equal(expected, result.ErrorCode);
    }

    private static FileTranscriptionSegmentRequest Request(
        AsrProviderId provider,
        RecognitionLanguage language) => new(
            "job-1",
            provider,
            language,
            new FileTranscriptionWindow(0, 0, 1_000),
            "segment.wav",
            string.Empty,
            0);

    private sealed class CapturingSessionFactory(FakeSession session)
        : IFileTranscriptionSessionFactory
    {
        public List<(AsrProviderId Provider, RecognitionLanguage Language)> Requests { get; } = [];

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            AsrProviderId provider,
            RecognitionLanguage language,
            Guid generation,
            CancellationToken cancellationToken)
        {
            Requests.Add((provider, language));
            return ValueTask.FromResult<IDictationAsrSession>(session);
        }
    }

    private sealed class CapturingProviderSessionAdapter(AsrProviderId provider)
        : IFileTranscriptionProviderSessionAdapter
    {
        public AsrProviderId Provider { get; } = provider;

        public List<RecognitionLanguage> RequestedLanguages { get; } = [];

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            RecognitionLanguage language,
            Guid generation,
            CancellationToken cancellationToken)
        {
            RequestedLanguages.Add(language);
            return ValueTask.FromResult<IDictationAsrSession>(new FakeSession("unused"));
        }
    }

    private sealed class FakeProvider(
        FakeSession session,
        AsrProviderAvailability availability = AsrProviderAvailability.Ready)
        : IDictationAsrProvider
    {
        public AsrProviderAvailability Availability { get; } = availability;

        public List<Guid> Generations { get; } = [];

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken)
        {
            Generations.Add(generation);
            return ValueTask.FromResult<IDictationAsrSession>(session);
        }
    }

    private sealed class FakePcmFrameSource(IReadOnlyList<byte[]> frames)
        : IFileTranscriptionPcmFrameSource
    {
        public async IAsyncEnumerable<ReadOnlyMemory<byte>> ReadFramesAsync(
            string audioPath,
            [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
        {
            foreach (var frame in frames)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return frame;
                await Task.Yield();
            }
        }
    }

    private sealed class FixedWavePcmFrameSource : IFileTranscriptionPcmFrameSource
    {
        public async IAsyncEnumerable<ReadOnlyMemory<byte>> ReadFramesAsync(
            string audioPath,
            [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
        {
            var wave = File.ReadAllBytes(Path.Combine(
                AppContext.BaseDirectory,
                "TestResources",
                "FileTranscriptionMedia",
                "tone.wav"));
            Assert.True(wave.AsSpan(0, 4).SequenceEqual("RIFF"u8));
            Assert.True(wave.AsSpan(8, 4).SequenceEqual("WAVE"u8));
            for (var offset = 44; offset < wave.Length; offset += 3_200)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return wave.AsMemory(offset, Math.Min(3_200, wave.Length - offset));
                await Task.Yield();
            }
        }
    }

    private sealed class BlockingPcmFrameSource : IFileTranscriptionPcmFrameSource
    {
        public async IAsyncEnumerable<ReadOnlyMemory<byte>> ReadFramesAsync(
            string audioPath,
            [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            yield break;
        }
    }

    private sealed class FakeSession(
        string? finalText,
        VoxFlowError? failure = null,
        Exception? startError = null) : IDictationAsrSession
    {
        public event EventHandler<AsrPartialResult>? PartialReceived
        {
            add { }
            remove { }
        }
        public event EventHandler<AsrFinalResult>? FinalReceived;
        private event EventHandler<VoxFlowError>? failed;

        public event EventHandler<VoxFlowError>? Failed
        {
            add => failed += value;
            remove => failed -= value;
        }

        public bool Started { get; private set; }
        public bool Finished { get; private set; }
        public bool Cancelled { get; private set; }
        public List<byte[]> Frames { get; } = [];
        public TaskCompletionSource StartedSignal { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask StartAsync(CancellationToken cancellationToken)
        {
            Started = true;
            StartedSignal.TrySetResult();
            if (startError is not null)
            {
                throw startError;
            }
            return ValueTask.CompletedTask;
        }

        public ValueTask PushAudioAsync(
            ReadOnlyMemory<byte> pcmS16LittleEndian,
            CancellationToken cancellationToken)
        {
            Frames.Add(pcmS16LittleEndian.ToArray());
            return ValueTask.CompletedTask;
        }

        public ValueTask FinishAsync(CancellationToken cancellationToken)
        {
            Finished = true;
            if (failure is not null)
            {
                failed?.Invoke(this, failure);
            }
            else if (finalText is not null)
            {
                FinalReceived?.Invoke(this, new AsrFinalResult(finalText));
            }
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken)
        {
            Cancelled = true;
            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class FakeProviderException(VoxFlowError error)
        : Exception, IFileTranscriptionProviderErrorException
    {
        public VoxFlowError Error { get; } = error;
    }
}
