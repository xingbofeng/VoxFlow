using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class FileTranscriptionPageViewModelTests
{
    [Fact]
    public async Task Multi_file_import_preserves_selection_order_and_snapshots_provider_and_language()
    {
        var jobs = new ImportJobRepository();
        var queue = new CapturingQueueExecutor();
        await using var queueService = new FileTranscriptionQueueService(queue);
        var ids = new Queue<string>(["job-1", "job-2", "job-3"]);
        var viewModel = new FileTranscriptionPageViewModel(
            "heading",
            "subtitle",
            jobs,
            queueService,
            () => new AsrSelection(AsrProviderId.AliyunDashScope, null),
            () => RecognitionLanguage.Japanese,
            TimeProvider.System,
            () => ids.Dequeue());

        var added = viewModel.ImportFiles(
        [
            @"C:\Media\one.mp3",
            @"C:\Media\two.m4a",
            @"C:\Media\three.mov",
        ], startImmediately: false);

        Assert.Equal(["job-1", "job-2", "job-3"], added.Select(job => job.Id));
        Assert.Equal(["one.mp3", "two.m4a", "three.mov"], added.Select(job => job.DisplayName));
        Assert.All(added, job =>
        {
            Assert.Equal(AsrProviderId.AliyunDashScope, job.Provider);
            Assert.Equal(RecognitionLanguage.Japanese, job.Language);
            Assert.Equal(FileTranscriptionJobStatus.Queued, job.Status);
        });
        Assert.Equal(added, viewModel.Jobs);
    }

    [Theory]
    [InlineData("readme.txt")]
    [InlineData("archive.zip")]
    [InlineData("no-extension")]
    public async Task Unsupported_drop_is_rejected_without_creating_a_job(string fileName)
    {
        var jobs = new ImportJobRepository();
        await using var queue = new FileTranscriptionQueueService(new CapturingQueueExecutor());
        var viewModel = Create(jobs, queue);

        var result = viewModel.ImportFiles([$@"C:\Media\{fileName}"], startImmediately: true);

        Assert.Empty(result);
        Assert.Empty(jobs.List());
        Assert.NotNull(viewModel.LastError);
    }

    [Fact]
    public async Task Drop_import_can_start_all_valid_jobs_in_fifo_order()
    {
        var jobs = new ImportJobRepository();
        var executor = new CapturingQueueExecutor();
        await using var queue = new FileTranscriptionQueueService(executor);
        var ids = new Queue<string>(["job-1", "job-2"]);
        var viewModel = new FileTranscriptionPageViewModel(
            "heading",
            "subtitle",
            jobs,
            queue,
            () => new AsrSelection(AsrProviderId.TencentCloud, null),
            () => RecognitionLanguage.ChineseMandarin,
            TimeProvider.System,
            () => ids.Dequeue());

        viewModel.ImportFiles(
            [@"C:\Media\one.wav", @"C:\Media\two.mp4"],
            startImmediately: true);
        await queue.WhenIdleAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(["job-1", "job-2"], executor.JobIds);
    }

    private static FileTranscriptionPageViewModel Create(
        ImportJobRepository jobs,
        FileTranscriptionQueueService queue) => new(
            "heading",
            "subtitle",
            jobs,
            queue,
            () => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B),
            () => RecognitionLanguage.Automatic,
            TimeProvider.System);

    private sealed class CapturingQueueExecutor : IFileTranscriptionJobExecutor
    {
        public List<string> JobIds { get; } = [];
        public Task ExecuteAsync(string jobId, Guid runId, CancellationToken cancellationToken)
        {
            JobIds.Add(jobId);
            return Task.CompletedTask;
        }
    }

    private sealed class ImportJobRepository : IFileTranscriptionJobRepository
    {
        private readonly List<FileTranscriptionJob> jobs = [];
        public void Create(FileTranscriptionJob job) => jobs.Add(job);
        public FileTranscriptionJob? Get(string id) => jobs.SingleOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs.ToArray();
        public bool Update(FileTranscriptionJob job) => throw new NotSupportedException();
        public bool Delete(string id) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }
}
