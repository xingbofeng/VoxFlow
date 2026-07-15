using System.Collections.Immutable;

namespace VoxFlow.Windows.Application.State;

/// <summary>
/// Atomically publishes one coherent group of non-secret setting values.
/// Secrets remain in the credential vault and must never be placed here.
/// </summary>
public sealed class UpdateSettingsCommand : IVoxFlowStateCommand
{
    private readonly IReadOnlyDictionary<string, string?> values;
    private readonly StateChangeKind changes;

    public UpdateSettingsCommand(
        IReadOnlyDictionary<string, string?> values,
        StateChangeKind changes = StateChangeKind.Settings)
    {
        this.values = values ?? throw new ArgumentNullException(nameof(values));
        if (values.Keys.Any(string.IsNullOrWhiteSpace))
        {
            throw new ArgumentException("Setting keys cannot be blank.", nameof(values));
        }

        if (changes == StateChangeKind.None
            || (changes & ~StateChangeKind.All) != StateChangeKind.None)
        {
            throw new ArgumentOutOfRangeException(nameof(changes));
        }

        this.changes = changes;
    }

    public StateMutation Apply(VoxFlowState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        ImmutableDictionary<string, string>.Builder builder =
            state.Settings.ToBuilder();
        foreach (var (key, value) in values)
        {
            if (value is null)
            {
                builder.Remove(key);
            }
            else
            {
                builder[key] = value;
            }
        }

        return new StateMutation(state.WithSettings(builder.ToImmutable()), changes);
    }
}
