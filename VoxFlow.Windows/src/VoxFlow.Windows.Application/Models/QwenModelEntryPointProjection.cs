using System.Text.Json;
using System.Text.Json.Serialization;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Models;

public sealed record QwenModelCardState(
    string Id,
    string DisplayName,
    QwenVariant Variant,
    ModelInstallPhase Phase,
    long BytesDownloaded,
    long TotalBytes,
    bool IsSelected,
    bool IsReady,
    bool IsSelectable,
    string? ErrorCode)
{
    public double Progress => TotalBytes == 0
        ? 0
        : Math.Clamp((double)BytesDownloaded / TotalBytes, 0, 1);
}

public sealed record QwenModelEntryPointSnapshot(
    long Version,
    IReadOnlyList<QwenModelCardState> Models)
{
    public IReadOnlyList<QwenModelCardState> Home => Models;

    public IReadOnlyList<QwenModelCardState> Settings => Models;

    public IReadOnlyList<QwenModelCardState> Menu => Models;
}

public sealed class QwenModelEntryPointProjection : IDisposable
{
    private readonly IDisposable subscription;
    private QwenModelEntryPointSnapshot current = new(0, Array.Empty<QwenModelCardState>());

    public QwenModelEntryPointProjection(VoxFlowStateStore stateStore)
    {
        ArgumentNullException.ThrowIfNull(stateStore);
        subscription = stateStore.Subscribe(Refresh);
    }

    public QwenModelEntryPointSnapshot Current => Volatile.Read(ref current);

    public event Action<QwenModelEntryPointSnapshot>? Changed;

    public void Dispose() => subscription.Dispose();

    private void Refresh(StateChanged change)
    {
        if ((change.Changes & (StateChangeKind.Models | StateChangeKind.ProviderSelection | StateChangeKind.All)) == 0)
        {
            return;
        }

        var selectedId = change.Snapshot.State.Settings.TryGetValue(
            QwenModelStateSynchronizer.SelectedModelKey,
            out var selected)
            ? selected
            : null;
        var cards = change.Snapshot.State.Settings
            .Where(pair =>
                pair.Key.StartsWith(QwenModelStateSynchronizer.ModelKeyPrefix, StringComparison.Ordinal)
                && !pair.Key.Equals(QwenModelStateSynchronizer.SelectedModelKey, StringComparison.Ordinal))
            .Select(pair => JsonSerializer.Deserialize<StoredQwenModelState>(pair.Value, SerializerOptions)
                ?? throw new InvalidDataException("Stored Qwen model projection is empty."))
            .OrderBy(model => model.Variant)
            .Select(model =>
            {
                var runtimeAllowed = model.RuntimePublishable;
                var ready = model.Phase == ModelInstallPhase.Ready && runtimeAllowed;
                return new QwenModelCardState(
                    model.Id,
                    model.DisplayName,
                    model.Variant,
                    model.Phase,
                    model.BytesDownloaded,
                    model.TotalBytes,
                    ready && string.Equals(model.Id, selectedId, StringComparison.Ordinal),
                    ready,
                    ready,
                    runtimeAllowed ? model.ErrorCode : "runtime_provenance_blocked");
            })
            .ToArray();
        var snapshot = new QwenModelEntryPointSnapshot(change.Snapshot.Version, cards);
        Volatile.Write(ref current, snapshot);
        Changed?.Invoke(snapshot);
    }

    internal static JsonSerializerOptions SerializerOptions { get; } = new()
    {
        Converters = { new JsonStringEnumConverter() },
    };
}

public sealed class QwenModelStateSynchronizer : IModelInstallStatePublisher
{
    internal const string ModelKeyPrefix = "models.qwen.";
    internal const string SelectedModelKey = "models.qwen.selected";
    private readonly VoxFlowStateStore stateStore;

    public QwenModelStateSynchronizer(VoxFlowStateStore stateStore)
    {
        this.stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
    }

    public void Publish(QwenModelManifest manifest, ModelInstallRecord state)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentNullException.ThrowIfNull(state);
        if (!string.Equals(manifest.Id, state.ModelId, StringComparison.Ordinal)
            || !string.Equals(manifest.ModelRevision, state.Version, StringComparison.Ordinal))
        {
            throw new ArgumentException("Model projection state does not match its manifest.", nameof(state));
        }

        _ = stateStore.Dispatch(new PublishCommand(manifest, state));
    }

    public void Select(string modelId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelId);
        _ = stateStore.Dispatch(new SelectCommand(modelId));
    }

    private sealed record PublishCommand(
        QwenModelManifest Manifest,
        ModelInstallRecord ModelState) : IVoxFlowStateCommand
    {
        public StateMutation Apply(VoxFlowState state)
        {
            var stored = new StoredQwenModelState(
                Manifest.Id,
                Manifest.DisplayName,
                Manifest.Variant,
                ModelState.Phase,
                ModelState.BytesDownloaded,
                ModelState.TotalBytes,
                Manifest.RuntimeGate.IsPublishable,
                ModelState.ErrorCode);
            var settings = state.Settings.SetItem(
                ModelKeyPrefix + Manifest.Id,
                JsonSerializer.Serialize(stored, QwenModelEntryPointProjection.SerializerOptions));
            if ((ModelState.Phase != ModelInstallPhase.Ready
                    || !Manifest.RuntimeGate.IsPublishable)
                && settings.TryGetValue(SelectedModelKey, out var selected)
                && string.Equals(selected, Manifest.Id, StringComparison.Ordinal))
            {
                settings = settings.Remove(SelectedModelKey);
            }

            return new StateMutation(
                state.WithSettings(settings),
                StateChangeKind.Models | StateChangeKind.ProviderSelection);
        }
    }

    private sealed record SelectCommand(string ModelId) : IVoxFlowStateCommand
    {
        public StateMutation Apply(VoxFlowState state)
        {
            if (!state.Settings.TryGetValue(ModelKeyPrefix + ModelId, out var json))
            {
                throw new InvalidOperationException("The Qwen model is unavailable.");
            }

            var model = JsonSerializer.Deserialize<StoredQwenModelState>(
                json,
                QwenModelEntryPointProjection.SerializerOptions)
                ?? throw new InvalidDataException("Stored Qwen model projection is empty.");
            if (model.Phase != ModelInstallPhase.Ready || !model.RuntimePublishable)
            {
                throw new InvalidOperationException("The Qwen model is not ready and selectable.");
            }

            return new StateMutation(
                state.WithSettings(state.Settings.SetItem(SelectedModelKey, ModelId)),
                StateChangeKind.ProviderSelection);
        }
    }
}

internal sealed record StoredQwenModelState(
    string Id,
    string DisplayName,
    QwenVariant Variant,
    ModelInstallPhase Phase,
    long BytesDownloaded,
    long TotalBytes,
    bool RuntimePublishable,
    string? ErrorCode);
