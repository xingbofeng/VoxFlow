using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.App.Tests;

public sealed class ResolvingDictationAsrProviderTests
{
    [Fact]
    public void Missing_selection_is_reported_as_unconfigured()
    {
        var provider = new ResolvingDictationAsrProvider(() => null);

        Assert.Equal(AsrProviderAvailability.Unconfigured, provider.Availability);
    }

    [Fact]
    public async Task Session_creation_uses_the_provider_selected_at_start_time()
    {
        var first = new FakeProvider();
        var second = new FakeProvider();
        IDictationAsrProvider selected = first;
        var provider = new ResolvingDictationAsrProvider(() => selected);

        selected = second;
        var session = await provider.CreateSessionAsync(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Same(second.Session, session);
        Assert.Equal(0, first.CreateCount);
        Assert.Equal(1, second.CreateCount);
    }

    [Fact]
    public async Task Factory_provider_exposes_readiness_and_creates_one_session()
    {
        var session = new FakeSession();
        var createCount = 0;
        var provider = new FactoryDictationAsrProvider(
            AsrProviderAvailability.Ready,
            (_, cancellationToken) =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                createCount++;
                return ValueTask.FromResult<IDictationAsrSession>(session);
            });

        var created = await provider.CreateSessionAsync(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Equal(AsrProviderAvailability.Ready, provider.Availability);
        Assert.Same(session, created);
        Assert.Equal(1, createCount);
    }

    private sealed class FakeProvider : IDictationAsrProvider
    {
        public FakeSession Session { get; } = new();

        public int CreateCount { get; private set; }

        public AsrProviderAvailability Availability => AsrProviderAvailability.Ready;

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken)
        {
            CreateCount++;
            return ValueTask.FromResult<IDictationAsrSession>(Session);
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

        public event EventHandler<VoxFlow.Windows.Domain.VoxFlowError>? Failed
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
