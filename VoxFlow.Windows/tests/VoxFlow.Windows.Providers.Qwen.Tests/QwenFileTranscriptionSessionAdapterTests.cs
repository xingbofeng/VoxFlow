using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen;

namespace VoxFlow.Windows.Providers.Qwen.Tests;

public sealed class QwenFileTranscriptionSessionAdapterTests
{
    [Fact]
    public async Task Adapter_reuses_the_recorded_language_and_existing_qwen_provider_session()
    {
        var session = new FakeSession();
        var provider = new FakeProvider(session);
        var languages = new List<RecognitionLanguage>();
        var adapter = new QwenFileTranscriptionSessionAdapter(language =>
        {
            languages.Add(language);
            return provider;
        });
        var generation = Guid.NewGuid();

        var restored = await adapter.CreateSessionAsync(
            RecognitionLanguage.Korean,
            generation,
            CancellationToken.None);

        Assert.Same(session, restored);
        Assert.Equal(AsrProviderId.Qwen, adapter.Provider);
        Assert.Equal([RecognitionLanguage.Korean], languages);
        Assert.Equal([generation], provider.Generations);
    }

    private sealed class FakeProvider(FakeSession session) : IDictationAsrProvider
    {
        public AsrProviderAvailability Availability => AsrProviderAvailability.Ready;

        public List<Guid> Generations { get; } = [];

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken)
        {
            Generations.Add(generation);
            return ValueTask.FromResult<IDictationAsrSession>(session);
        }
    }

    private sealed class FakeSession : IDictationAsrSession
    {
        public event EventHandler<AsrPartialResult>? PartialReceived
        {
            add { }
            remove { }
        }

        public event EventHandler<AsrFinalResult>? FinalReceived
        {
            add { }
            remove { }
        }

        public event EventHandler<VoxFlowError>? Failed
        {
            add { }
            remove { }
        }

        public ValueTask StartAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask PushAudioAsync(
            ReadOnlyMemory<byte> pcmS16LittleEndian,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;

        public ValueTask FinishAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask CancelAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
