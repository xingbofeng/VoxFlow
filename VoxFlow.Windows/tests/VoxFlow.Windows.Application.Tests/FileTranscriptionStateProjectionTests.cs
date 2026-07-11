using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionStateProjectionTests
{
    [Fact]
    public void Projection_publishes_one_read_only_summary_for_all_entry_points()
    {
        var store = new VoxFlowStateStore();
        var repository = new SummaryJobRepository(
        [
            Job("queued", FileTranscriptionJobStatus.Queued, 1),
            Job("running", FileTranscriptionJobStatus.Running, 2),
            Job("partial", FileTranscriptionJobStatus.PartiallyFailed, 3),
            Job("interrupted", FileTranscriptionJobStatus.Interrupted, 4),
            Job("completed", FileTranscriptionJobStatus.Completed, 5),
        ]);
        var changes = new List<StateChanged>();
        using var subscription = store.Subscribe(changes.Add, replayCurrent: false);
        var projection = new FileTranscriptionStateProjection(repository, store);

        var summary = projection.Refresh();

        Assert.Equal(5, summary.TotalCount);
        Assert.Equal(1, summary.QueuedCount);
        Assert.Equal(1, summary.RunningCount);
        Assert.Equal(2, summary.NeedsAttentionCount);
        Assert.Equal(1, summary.CompletedCount);
        Assert.Equal(summary, store.Current.State.FileTranscriptionSummary);
        Assert.Single(changes);
        Assert.Equal(StateChangeKind.FileTranscription, changes[0].Changes);
    }

    [Fact]
    public void Settings_updates_preserve_the_file_transcription_summary()
    {
        var store = new VoxFlowStateStore();
        store.Dispatch(new UpdateFileTranscriptionSummaryCommand(
            new FileTranscriptionTaskSummary(3, 1, 1, 0, 1)));

        store.Dispatch(new UpdateSettingsCommand(
            new Dictionary<string, string?> { ["theme"] = "dark" }));

        Assert.Equal(3, store.Current.State.FileTranscriptionSummary.TotalCount);
        Assert.Equal("dark", store.Current.State.Settings["theme"]);
    }

    private static FileTranscriptionJob Job(
        string id,
        FileTranscriptionJobStatus status,
        long createdAt) => new(
            id,
            $@"C:\Recordings\{id}.wav",
            $"{id}.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            createdAt,
            status: status,
            finalText: status is FileTranscriptionJobStatus.Completed
                or FileTranscriptionJobStatus.PartiallyFailed
                ? "text"
                : null,
            errorCode: status == FileTranscriptionJobStatus.Failed
                ? FileTranscriptionErrorCode.ProviderFailure
                : null);

    private sealed class SummaryJobRepository(IReadOnlyList<FileTranscriptionJob> jobs)
        : IFileTranscriptionJobRepository
    {
        public void Create(FileTranscriptionJob job) => throw new NotSupportedException();
        public FileTranscriptionJob? Get(string id) => jobs.SingleOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs;
        public bool Update(FileTranscriptionJob job) => throw new NotSupportedException();
        public bool Delete(string id) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }
}
