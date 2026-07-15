using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.History;

public enum UnifiedHistoryStorageKind
{
    DictationHistory,
    WorkflowTask,
    FileTranscription,
    Screenshot,
}

public enum UnifiedHistoryKind
{
    Dictation,
    SelectionTranslation,
    SelectionSummary,
    AgentCompose,
    FileTranscription,
    Screenshot,
}

public sealed class UnifiedHistoryEntry
{
    internal UnifiedHistoryEntry(
        string id,
        string storageId,
        UnifiedHistoryStorageKind storageKind,
        UnifiedHistoryKind kind,
        string title,
        string rawText,
        string resultText,
        string copyText,
        string additionalSearchText,
        string status,
        string? providerId,
        string? model,
        long? durationMilliseconds,
        DateTimeOffset createdAtUtc,
        HistoryEntry? dictationEntry = null,
        WorkflowTaskRecord? workflowTask = null,
        FileTranscriptionJob? fileTranscriptionJob = null,
        ScreenshotRecord? screenshotRecord = null)
    {
        Id = id;
        StorageId = storageId;
        StorageKind = storageKind;
        Kind = kind;
        Title = title;
        RawText = rawText;
        ResultText = resultText;
        CopyText = copyText;
        AdditionalSearchText = additionalSearchText;
        Status = status;
        ProviderId = providerId;
        Model = model;
        DurationMilliseconds = durationMilliseconds;
        CreatedAtUtc = createdAtUtc;
        DictationEntry = dictationEntry;
        WorkflowTask = workflowTask;
        FileTranscriptionJob = fileTranscriptionJob;
        ScreenshotRecord = screenshotRecord;
    }

    public string Id { get; }

    public string StorageId { get; }

    public UnifiedHistoryStorageKind StorageKind { get; }

    public UnifiedHistoryKind Kind { get; }

    public string Title { get; }

    public string RawText { get; }

    public string ResultText { get; }

    public string CopyText { get; }

    public string Status { get; }

    public string? ProviderId { get; }

    public string? Model { get; }

    public long? DurationMilliseconds { get; }

    public DateTimeOffset CreatedAtUtc { get; }

    public HistoryEntry? DictationEntry { get; }

    public WorkflowTaskRecord? WorkflowTask { get; }

    public FileTranscriptionJob? FileTranscriptionJob { get; }

    public ScreenshotRecord? ScreenshotRecord { get; }

    public string? ImagePath => ScreenshotRecord?.ThumbnailPath
        ?? ScreenshotRecord?.RenderedImagePath
        ?? ScreenshotRecord?.OriginalImagePath;

    internal string AdditionalSearchText { get; }

    public bool Matches(string searchText)
    {
        ArgumentNullException.ThrowIfNull(searchText);
        var term = searchText.Trim();
        return term.Length == 0
            || Title.Contains(term, StringComparison.OrdinalIgnoreCase)
            || RawText.Contains(term, StringComparison.OrdinalIgnoreCase)
            || ResultText.Contains(term, StringComparison.OrdinalIgnoreCase)
            || AdditionalSearchText.Contains(term, StringComparison.OrdinalIgnoreCase)
            || (ProviderId?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false)
            || (Model?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false);
    }
}

public sealed class UnifiedHistoryQuery
{
    public UnifiedHistoryQuery(
        string? searchText,
        UnifiedHistoryKind? kind,
        int offset,
        int limit)
    {
        if (kind is not null && !Enum.IsDefined(kind.Value))
        {
            throw new ArgumentOutOfRangeException(nameof(kind), kind, null);
        }
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        if (limit is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(limit));
        }

        SearchText = string.IsNullOrWhiteSpace(searchText)
            ? null
            : searchText.Trim();
        Kind = kind;
        Offset = offset;
        Limit = limit;
    }

    public string? SearchText { get; }

    public UnifiedHistoryKind? Kind { get; }

    public int Offset { get; }

    public int Limit { get; }
}

public sealed record UnifiedHistoryPage(
    IReadOnlyList<UnifiedHistoryEntry> Items,
    int TotalCount,
    int Offset,
    int Limit);

public interface IUnifiedHistoryQueryService
{
    IReadOnlyList<UnifiedHistoryEntry> ReadAll();

    UnifiedHistoryPage Search(UnifiedHistoryQuery query);
}

public interface IUnifiedHistoryService : IUnifiedHistoryQueryService
{
    int Delete(IReadOnlyCollection<string> ids);

    int Clear();
}

public sealed class UnifiedHistoryQueryService : IUnifiedHistoryService
{
    private const int WorkflowPageSize = 100;

    private const int ScreenshotPageSize = 100;

    private readonly IHistoryStore dictationHistory;
    private readonly IWorkflowTaskRepository? workflowTasks;
    private readonly IFileTranscriptionJobRepository? fileTranscriptionJobs;
    private readonly AgentSessionWorkspaceRetentionService? agentSessionWorkspaces;
    private readonly IScreenshotRecordRepository? screenshotRecords;

    public UnifiedHistoryQueryService(
        IHistoryStore dictationHistory,
        IWorkflowTaskRepository? workflowTasks = null,
        IFileTranscriptionJobRepository? fileTranscriptionJobs = null,
        AgentSessionWorkspaceRetentionService? agentSessionWorkspaces = null,
        IScreenshotRecordRepository? screenshotRecords = null)
    {
        this.dictationHistory = dictationHistory
            ?? throw new ArgumentNullException(nameof(dictationHistory));
        this.workflowTasks = workflowTasks;
        this.fileTranscriptionJobs = fileTranscriptionJobs;
        this.agentSessionWorkspaces = agentSessionWorkspaces;
        this.screenshotRecords = screenshotRecords;
    }

    public IReadOnlyList<UnifiedHistoryEntry> ReadAll()
    {
        var entries = new List<UnifiedHistoryEntry>();
        entries.AddRange(dictationHistory.ReadAll().Select(MapDictation));
        entries.AddRange(ReadAllWorkflows().Select(MapWorkflow));
        if (fileTranscriptionJobs is not null)
        {
            entries.AddRange(fileTranscriptionJobs.List().Select(MapFile));
        }

        entries.AddRange(ReadAllScreenshots().Select(MapScreenshot));
        return entries
            .OrderByDescending(entry => entry.CreatedAtUtc)
            .ThenBy(entry => entry.Id, StringComparer.Ordinal)
            .ToArray();
    }

    public UnifiedHistoryPage Search(UnifiedHistoryQuery query)
    {
        ArgumentNullException.ThrowIfNull(query);
        var filtered = ReadAll().Where(entry =>
                (query.Kind is null || entry.Kind == query.Kind)
                && (query.SearchText is null || entry.Matches(query.SearchText)))
            .ToArray();
        return new UnifiedHistoryPage(
            filtered.Skip(query.Offset).Take(query.Limit).ToArray(),
            filtered.Length,
            query.Offset,
            query.Limit);
    }

    public int Delete(IReadOnlyCollection<string> ids)
    {
        ArgumentNullException.ThrowIfNull(ids);
        var requested = ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .ToHashSet(StringComparer.Ordinal);
        if (requested.Count == 0)
        {
            return 0;
        }

        var entries = ReadAll()
            .Where(entry => requested.Contains(entry.Id))
            .ToArray();
        var deleted = dictationHistory.Delete(entries
            .Where(entry => entry.StorageKind
                == UnifiedHistoryStorageKind.DictationHistory)
            .Select(entry => entry.StorageId)
            .ToArray());
        if (workflowTasks is not null)
        {
            foreach (var entry in entries.Where(entry => entry.StorageKind
                         == UnifiedHistoryStorageKind.WorkflowTask))
            {
                if (!workflowTasks.Delete(entry.StorageId))
                {
                    continue;
                }

                deleted++;
                if (entry.Kind == UnifiedHistoryKind.AgentCompose)
                {
                    _ = agentSessionWorkspaces?.DeleteSessionForHistory(entry.StorageId);
                }
            }
        }
        if (fileTranscriptionJobs is not null)
        {
            deleted += entries.Count(entry => entry.StorageKind
                    == UnifiedHistoryStorageKind.FileTranscription
                && fileTranscriptionJobs.Delete(entry.StorageId));
        }
        if (screenshotRecords is not null)
        {
            var deletedAt = DateTimeOffset.UtcNow;
            foreach (var entry in entries.Where(entry => entry.StorageKind
                         == UnifiedHistoryStorageKind.Screenshot))
            {
                if (screenshotRecords.SoftDelete(entry.StorageId, deletedAt))
                {
                    deleted++;
                }
            }
        }
        return deleted;
    }

    public int Clear()
    {
        var deleted = dictationHistory.Clear();
        if (workflowTasks is not null)
        {
            foreach (var task in ReadAllWorkflows())
            {
                if (workflowTasks.Delete(task.Id))
                {
                    deleted++;
                    if (task.Kind == WorkflowTaskKind.AgentCompose)
                    {
                        _ = agentSessionWorkspaces?.DeleteSessionForHistory(task.Id);
                    }
                }
            }
        }
        if (fileTranscriptionJobs is not null)
        {
            foreach (var job in fileTranscriptionJobs.List())
            {
                if (fileTranscriptionJobs.Delete(job.Id))
                {
                    deleted++;
                }
            }
        }
        if (screenshotRecords is not null)
        {
            var deletedAt = DateTimeOffset.UtcNow;
            foreach (var record in ReadAllScreenshots())
            {
                if (screenshotRecords.SoftDelete(record.Id, deletedAt))
                {
                    deleted++;
                }
            }
        }
        return deleted;
    }

    private IReadOnlyList<WorkflowTaskRecord> ReadAllWorkflows()
    {
        if (workflowTasks is null)
        {
            return Array.Empty<WorkflowTaskRecord>();
        }

        List<WorkflowTaskRecord> tasks = [];
        var offset = 0;
        while (true)
        {
            var page = workflowTasks.Search(new WorkflowTaskQuery(
                searchText: null,
                kind: null,
                offset,
                WorkflowPageSize));
            tasks.AddRange(page.Items);
            if (page.Items.Count == 0 || tasks.Count >= page.TotalCount)
            {
                break;
            }
            offset += page.Items.Count;
        }
        return tasks;
    }

    private static UnifiedHistoryEntry MapDictation(HistoryEntry entry) => new(
        entry.Id,
        entry.Id,
        UnifiedHistoryStorageKind.DictationHistory,
        UnifiedHistoryKind.Dictation,
        entry.Source,
        entry.RawText,
        entry.FinalText,
        entry.FinalText,
        additionalSearchText: string.Empty,
        status: entry.Metadata.ErrorCode is null ? "completed" : "failed",
        providerId: entry.Metadata.AsrProvider?.ToString(),
        model: entry.Metadata.QwenVariant?.ToString(),
        entry.Metadata.DurationMilliseconds,
        entry.CreatedAtUtc,
        dictationEntry: entry);

    private static UnifiedHistoryEntry MapWorkflow(WorkflowTaskRecord task)
    {
        var result = FirstNonEmpty(task.FinalText, task.PartialText);
        return new UnifiedHistoryEntry(
            "workflow:" + task.Id,
            task.Id,
            UnifiedHistoryStorageKind.WorkflowTask,
            task.Kind switch
            {
                WorkflowTaskKind.SelectionTranslation =>
                    UnifiedHistoryKind.SelectionTranslation,
                WorkflowTaskKind.SelectionSummary =>
                    UnifiedHistoryKind.SelectionSummary,
                WorkflowTaskKind.AgentCompose => UnifiedHistoryKind.AgentCompose,
                _ => throw new ArgumentOutOfRangeException(nameof(task)),
            },
            task.Kind.ToString(),
            task.RawText ?? string.Empty,
            result,
            FirstNonEmpty(task.FinalText, task.PartialText, task.RawText),
            AdditionalWorkflowText(task),
            task.Status.ToString(),
            task.ProviderId,
            task.Model,
            task.CompletedAtUnixMs is { } completed
                ? Math.Max(0, completed - task.CreatedAtUnixMs)
                : null,
            DateTimeOffset.FromUnixTimeMilliseconds(task.CreatedAtUnixMs),
            workflowTask: task);
    }

    private IReadOnlyList<ScreenshotRecord> ReadAllScreenshots()
    {
        if (screenshotRecords is null)
        {
            return Array.Empty<ScreenshotRecord>();
        }

        List<ScreenshotRecord> records = [];
        var offset = 0;
        while (true)
        {
            var page = screenshotRecords.Search(new ScreenshotRecordQuery(
                searchText: null,
                favoritesOnly: false,
                offset,
                ScreenshotPageSize));
            records.AddRange(page.Items);
            if (page.Items.Count == 0 || records.Count >= page.TotalCount)
            {
                break;
            }

            offset += page.Items.Count;
        }

        return records;
    }

    private static UnifiedHistoryEntry MapScreenshot(ScreenshotRecord record)
    {
        var result = FirstNonEmpty(
            record.SummaryText,
            record.TranslatedText,
            record.RefinedText,
            record.OcrText,
            record.SourceWindowTitle);
        var title = string.IsNullOrWhiteSpace(record.SourceWindowTitle)
            ? "Screenshot"
            : record.SourceWindowTitle!;
        return new UnifiedHistoryEntry(
            "screenshot:" + record.Id,
            record.Id,
            UnifiedHistoryStorageKind.Screenshot,
            UnifiedHistoryKind.Screenshot,
            title,
            record.OcrText,
            result,
            FirstNonEmpty(result, record.OcrText, title),
            additionalSearchText: string.Join(
                ' ',
                new[]
                {
                    record.OcrText,
                    record.RefinedText,
                    record.TranslatedText,
                    record.SummaryText,
                    record.SourceWindowTitle,
                    record.SourceDisplayId,
                }.Where(static value => !string.IsNullOrWhiteSpace(value))),
            status: "completed",
            providerId: null,
            model: null,
            durationMilliseconds: null,
            record.CreatedAtUtc,
            screenshotRecord: record);
    }

    private static UnifiedHistoryEntry MapFile(FileTranscriptionJob job) => new(
        "file:" + job.Id,
        job.Id,
        UnifiedHistoryStorageKind.FileTranscription,
        UnifiedHistoryKind.FileTranscription,
        job.DisplayName,
        FirstNonEmpty(job.RawText, job.DisplayName),
        FirstNonEmpty(job.FinalText, job.TranslatedText),
        FirstNonEmpty(job.FinalText, job.TranslatedText, job.RawText, job.DisplayName),
        string.Join('\n', new[]
        {
            job.DisplayName,
            job.TranslatedText,
            job.PartialFailureSummary,
            job.ErrorCode?.ToString(),
            job.TranslationErrorCode?.ToString(),
        }.Where(value => !string.IsNullOrWhiteSpace(value))),
        job.Status.ToString(),
        job.Provider.ToString(),
        model: null,
        job.DurationMs,
        DateTimeOffset.FromUnixTimeMilliseconds(job.CreatedAtUnixMs),
        fileTranscriptionJob: job);

    private static string AdditionalWorkflowText(WorkflowTaskRecord task) =>
        string.Join('\n', new[]
        {
            task.FailureJson?.GetRawText(),
            task.WarningsJson?.GetRawText(),
        }.Where(value => !string.IsNullOrWhiteSpace(value)));

    private static string FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
}
