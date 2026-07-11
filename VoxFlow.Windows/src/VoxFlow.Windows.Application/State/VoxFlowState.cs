using System.Collections.Immutable;

namespace VoxFlow.Windows.Application.State;

/// <summary>
/// Immutable application state shared by every application entry point.
/// </summary>
public sealed record VoxFlowState
{
    private VoxFlowState(
        ImmutableDictionary<string, string> settings,
        FileTranscription.FileTranscriptionTaskSummary fileTranscriptionSummary)
    {
        Settings = settings ?? throw new ArgumentNullException(nameof(settings));
        FileTranscriptionSummary = fileTranscriptionSummary
            ?? throw new ArgumentNullException(nameof(fileTranscriptionSummary));
    }

    public static VoxFlowState Default { get; } = new(
        ImmutableDictionary.Create<string, string>(StringComparer.Ordinal),
        FileTranscription.FileTranscriptionTaskSummary.Empty);

    public ImmutableDictionary<string, string> Settings { get; }

    public FileTranscription.FileTranscriptionTaskSummary FileTranscriptionSummary { get; }

    public VoxFlowState WithSettings(ImmutableDictionary<string, string> settings) =>
        new(settings, FileTranscriptionSummary);

    public VoxFlowState WithFileTranscriptionSummary(
        FileTranscription.FileTranscriptionTaskSummary summary) =>
        new(Settings, summary);
}

/// <summary>
/// A coherent state value and its monotonically increasing store version.
/// </summary>
public sealed record VoxFlowStateSnapshot(long Version, VoxFlowState State);

/// <summary>
/// Categories that let subscribers refresh only the views they own.
/// </summary>
[Flags]
public enum StateChangeKind
{
    None = 0,
    Settings = 1 << 0,
    ProviderSelection = 1 << 1,
    Models = 1 << 2,
    Llm = 1 << 3,
    History = 1 << 4,
    Ui = 1 << 5,
    Dictation = 1 << 6,
    FileTranscription = 1 << 7,
    All = Settings
        | ProviderSelection
        | Models
        | Llm
        | History
        | Ui
        | Dictation
        | FileTranscription,
}

/// <summary>
/// The pure result of applying a command to an immutable state value.
/// </summary>
public sealed record StateMutation(VoxFlowState State, StateChangeKind Changes);

/// <summary>
/// Commands are pure reducers. The store may reapply one when a concurrent
/// command commits first.
/// </summary>
public interface IVoxFlowStateCommand
{
    StateMutation Apply(VoxFlowState state);
}

/// <summary>
/// One shared notification instance published to every current subscriber.
/// </summary>
public sealed record StateChanged(
    VoxFlowStateSnapshot Snapshot,
    StateChangeKind Changes);
