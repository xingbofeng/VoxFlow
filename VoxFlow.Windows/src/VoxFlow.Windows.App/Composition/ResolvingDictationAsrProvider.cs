using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.App.Composition;

public sealed class ResolvingDictationAsrProvider : IDictationAsrProvider
{
    private readonly Func<IDictationAsrProvider?> resolve;

    public ResolvingDictationAsrProvider(Func<IDictationAsrProvider?> resolve)
    {
        this.resolve = resolve ?? throw new ArgumentNullException(nameof(resolve));
    }

    public AsrProviderAvailability Availability =>
        resolve()?.Availability ?? AsrProviderAvailability.Unconfigured;

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        var selected = resolve()
            ?? throw new InvalidOperationException("No ASR provider is selected.");
        return selected.CreateSessionAsync(generation, cancellationToken);
    }
}

public sealed class FactoryDictationAsrProvider : IDictationAsrProvider
{
    private readonly Func<Guid, CancellationToken, ValueTask<IDictationAsrSession>>
        createSession;

    public FactoryDictationAsrProvider(
        AsrProviderAvailability availability,
        Func<Guid, CancellationToken, ValueTask<IDictationAsrSession>> createSession)
    {
        if (!Enum.IsDefined(availability))
        {
            throw new ArgumentOutOfRangeException(nameof(availability));
        }
        Availability = availability;
        this.createSession = createSession
            ?? throw new ArgumentNullException(nameof(createSession));
    }

    public AsrProviderAvailability Availability { get; }

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        Guid generation,
        CancellationToken cancellationToken) =>
        createSession(generation, cancellationToken);
}
