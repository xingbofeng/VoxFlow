using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.FileTranscription;

public sealed class FileTranscriptionPageViewModel : INotifyPropertyChanged
{
    private static readonly HashSet<string> SupportedExtensions = new(
        [".mp3", ".wav", ".m4a", ".aac", ".mp4", ".mov"],
        StringComparer.OrdinalIgnoreCase);

    private readonly IFileTranscriptionJobRepository? jobs;
    private readonly FileTranscriptionQueueService? queue;
    private readonly Func<AsrSelection?> selectionProvider;
    private readonly Func<RecognitionLanguage> languageProvider;
    private readonly TimeProvider timeProvider;
    private readonly Func<string> idProvider;
    private readonly IFileTranscriptionSegmentRepository? segments;
    private readonly FileTranscriptionJobLifecycleService? lifecycle;
    private readonly FileTranscriptionCopyService? copyService;
    private readonly FileTranscriptionExportService? exportService;
    private readonly FileTranscriptionTranslationService? translationService;
    private readonly FileTranscriptionPlaybackService? playbackService;
    private readonly Action? stateRefresh;
    private long lastCreatedAtUnixMs;
    private string? lastError;
    private string? lastActionMessage;
    private FileTranscriptionJob? selectedJob;
    private FileTranscriptionJobPresentation? selectedItem;
    private FileTranscriptionPlaybackState playbackState = FileTranscriptionPlaybackState.Stopped;
    private string? playbackJobId;
    private bool isTranslationRequestRunning;

    public FileTranscriptionPageViewModel(string heading, string subtitle)
        : this(
            heading,
            subtitle,
            jobs: null,
            queue: null,
            selectionProvider: () => null,
            languageProvider: () => RecognitionLanguage.Automatic,
            TimeProvider.System)
    {
    }

    public FileTranscriptionPageViewModel(
        string heading,
        string subtitle,
        IFileTranscriptionJobRepository? jobs,
        FileTranscriptionQueueService? queue,
        Func<AsrSelection?> selectionProvider,
        Func<RecognitionLanguage> languageProvider,
        TimeProvider timeProvider,
        Func<string>? idProvider = null,
        IFileTranscriptionSegmentRepository? segments = null,
        FileTranscriptionJobLifecycleService? lifecycle = null,
        FileTranscriptionCopyService? copyService = null,
        FileTranscriptionExportService? exportService = null,
        FileTranscriptionTranslationService? translationService = null,
        FileTranscriptionPlaybackService? playbackService = null,
        Action? stateRefresh = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(heading);
        ArgumentNullException.ThrowIfNull(subtitle);
        Heading = heading;
        Subtitle = subtitle;
        this.jobs = jobs;
        this.queue = queue;
        this.selectionProvider = selectionProvider
            ?? throw new ArgumentNullException(nameof(selectionProvider));
        this.languageProvider = languageProvider
            ?? throw new ArgumentNullException(nameof(languageProvider));
        this.timeProvider = timeProvider
            ?? throw new ArgumentNullException(nameof(timeProvider));
        this.idProvider = idProvider ?? (() => Guid.NewGuid().ToString("N"));
        this.segments = segments;
        this.lifecycle = lifecycle;
        this.copyService = copyService;
        this.exportService = exportService;
        this.translationService = translationService;
        this.playbackService = playbackService;
        this.stateRefresh = stateRefresh;
        Jobs = new ObservableCollection<FileTranscriptionJob>(jobs?.List() ?? []);
        JobItems = new ObservableCollection<FileTranscriptionJobPresentation>(
            Jobs.Select(CreatePresentation));
        lastCreatedAtUnixMs = Jobs.Count == 0
            ? -1
            : Jobs.Max(job => job.CreatedAtUnixMs);
        SelectedItem = JobItems.FirstOrDefault();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Heading { get; }
    public string Subtitle { get; }
    public ObservableCollection<FileTranscriptionJob> Jobs { get; }
    public ObservableCollection<FileTranscriptionJobPresentation> JobItems { get; }

    public FileTranscriptionJob? SelectedJob
    {
        get => selectedJob;
        set
        {
            if (Equals(selectedJob, value)) return;
            selectedJob = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasSelectedJob));
        }
    }

    public FileTranscriptionJobPresentation? SelectedItem
    {
        get => selectedItem;
        set
        {
            if (ReferenceEquals(selectedItem, value)) return;
            selectedItem = value;
            selectedJob = value?.Job;
            OnPropertyChanged();
            OnPropertyChanged(nameof(SelectedJob));
            OnPropertyChanged(nameof(HasSelectedJob));
            OnPropertyChanged(nameof(IsSelectedPlaying));
            OnPropertyChanged(nameof(PlaybackLabel));
            OnPropertyChanged(nameof(IsTranslationInProgress));
        }
    }

    public bool HasSelectedJob => SelectedJob is not null;
    public bool IsSelectedPlaying => SelectedJob?.Id == playbackJobId
        && playbackState == FileTranscriptionPlaybackState.Playing;
    public bool IsTranslationRequestRunning
    {
        get => isTranslationRequestRunning;
        private set
        {
            if (isTranslationRequestRunning == value) return;
            isTranslationRequestRunning = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsTranslationInProgress));
        }
    }
    public bool IsTranslationInProgress => IsTranslationRequestRunning
        || SelectedItem?.IsTranslating == true;
    public bool HasRunningJob => JobItems.Any(item => item.IsRunning);
    public int RunningProgressPercent => JobItems.FirstOrDefault(item => item.IsRunning)
        ?.ProgressPercent ?? 0;
    public string JobCountSummary => string.Format(
        System.Globalization.CultureInfo.CurrentUICulture,
        L10n.Localize("FileTranscriptionStatusJobCount"),
        JobItems.Count);

    public string? LastError
    {
        get => lastError;
        private set
        {
            if (lastError == value) return;
            lastError = value;
            OnPropertyChanged();
        }
    }

    public string? LastActionMessage
    {
        get => lastActionMessage;
        private set
        {
            if (lastActionMessage == value) return;
            lastActionMessage = value;
            OnPropertyChanged();
        }
    }

    public string BrowseLabel => L10n.Localize("FileTranscriptionBrowse");
    public string DropTitle => L10n.Localize("FileTranscriptionDropTitle");
    public string SupportedFormats => L10n.Localize("FileTranscriptionSupportedFormats");
    public string QueueTitle => L10n.Localize("FileTranscriptionQueueTitle");
    public string QueueEmpty => L10n.Localize("FileTranscriptionQueueEmpty");
    public string ResultTitle => L10n.Localize("FileTranscriptionResultTitle");
    public string ResultEmpty => L10n.Localize("FileTranscriptionResultEmpty");
    public string Status => LastError
        ?? JobItems.FirstOrDefault(item => item.IsRunning)?.ProcessingSegmentLine
        ?? LastActionMessage
        ?? L10n.Localize(JobItems.Count == 0
            ? "FileTranscriptionStatusReady"
            : "FileTranscriptionStatusIdle");
    public string StartLabel => L10n.Localize("FileTranscriptionActionStart");
    public string CancelLabel => L10n.Localize("FileTranscriptionActionCancel");
    public string ContinueLabel => L10n.Localize("FileTranscriptionActionContinue");
    public string RetryLabel => L10n.Localize("FileTranscriptionActionRetry");
    public string DeleteLabel => L10n.Localize("FileTranscriptionActionDelete");
    public string CopyLabel => L10n.Localize("FileTranscriptionActionCopy");
    public string ExportLabel => L10n.Localize("FileTranscriptionActionExport");
    public string TranslateLabel => L10n.Localize("FileTranscriptionActionTranslate");
    public string PlaybackLabel => L10n.Localize(IsSelectedPlaying
        ? "FileTranscriptionActionPause"
        : "FileTranscriptionActionPlay");
    public string OriginalLabel => L10n.Localize("FileTranscriptionOriginalHeading");
    public string TranslationLabel => L10n.Localize("FileTranscriptionTranslationHeading");
    public string DiagnosticsLabel => L10n.Localize("FileTranscriptionDiagnosticsHeading");
    public string ResultUnavailableHelp => L10n.Localize("FileTranscriptionResultUnavailableHelp");
    public string PlaybackUnavailableHelp => L10n.Localize("FileTranscriptionPlaybackUnavailableHelp");

    public IReadOnlyList<FileTranscriptionJob> ImportFiles(
        IEnumerable<string> sourcePaths,
        bool startImmediately)
    {
        ArgumentNullException.ThrowIfNull(sourcePaths);
        if (jobs is null)
        {
            return [];
        }

        var selection = selectionProvider();
        if (selection is null)
        {
            LastError = L10n.Localize("FileTranscriptionProviderUnavailable");
            OnPropertyChanged(nameof(Status));
            return [];
        }
        var language = languageProvider();
        List<FileTranscriptionJob> added = [];
        foreach (var sourcePath in sourcePaths)
        {
            if (string.IsNullOrWhiteSpace(sourcePath)
                || !SupportedExtensions.Contains(Path.GetExtension(sourcePath)))
            {
                LastError = L10n.Localize("FileTranscriptionUnsupportedFormat");
                continue;
            }

            var createdAt = Math.Max(
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds(),
                lastCreatedAtUnixMs + 1);
            lastCreatedAtUnixMs = createdAt;
            var job = new FileTranscriptionJob(
                idProvider(),
                Path.GetFullPath(sourcePath),
                Path.GetFileName(sourcePath),
                selection.Provider,
                language,
                createdAt);
            jobs.Create(job);
            Jobs.Add(job);
            JobItems.Add(CreatePresentation(job));
            added.Add(job);
            if (startImmediately)
            {
                _ = queue?.TryEnqueue(job.Id);
            }
        }

        if (added.Count > 0)
        {
            SelectedItem ??= JobItems.First(item => item.Id == added[0].Id);
            LastError = null;
            LastActionMessage = L10n.Localize("FileTranscriptionJobsAdded");
            OnPropertyChanged(nameof(Status));
            stateRefresh?.Invoke();
        }
        return added;
    }

    public bool StartSelected()
    {
        if (SelectedItem is not { CanStart: true } item || queue is null) return false;
        var started = queue.TryEnqueue(item.Id);
        if (started) SetFeedback("FileTranscriptionFeedbackStarted");
        return started;
    }

    public bool CancelSelected() => ApplyLifecycle(
        item => item.CanCancel,
        id => lifecycle?.Cancel(id) == true,
        "FileTranscriptionFeedbackCancelled");

    public bool ContinueSelected() => ApplyLifecycle(
        item => item.CanContinue,
        id => lifecycle?.Continue(id) == true,
        "FileTranscriptionFeedbackContinued");

    public bool RetrySelected() => ApplyLifecycle(
        item => item.CanRetry,
        id => lifecycle?.RetryFromBeginning(id) == true,
        "FileTranscriptionFeedbackRetried");

    private bool DeleteSelectedCore() => ApplyLifecycle(
        _ => true,
        id => lifecycle?.Delete(id) == true,
        "FileTranscriptionFeedbackDeleted");

    public async ValueTask<bool> DeleteSelectedAsync(CancellationToken cancellationToken)
    {
        if (SelectedItem is null) return false;
        if (playbackService is not null && playbackJobId == SelectedItem.Id)
        {
            await playbackService.StopAsync(cancellationToken);
            playbackJobId = null;
            playbackState = FileTranscriptionPlaybackState.Stopped;
            OnPropertyChanged(nameof(IsSelectedPlaying));
            OnPropertyChanged(nameof(PlaybackLabel));
        }
        return DeleteSelectedCore();
    }

    public FileTranscriptionCopyResult CopySelected()
    {
        if (SelectedJob is null || copyService is null)
        {
            return FileTranscriptionCopyResult.ResultUnavailable;
        }
        var result = copyService.Copy(SelectedJob);
        SetFeedback(result == FileTranscriptionCopyResult.Succeeded
            ? "FileTranscriptionFeedbackCopied"
            : "FileTranscriptionFeedbackCopyFailed",
            isError: result != FileTranscriptionCopyResult.Succeeded);
        return result;
    }

    public async ValueTask<FileTranscriptionExportResult?> ExportSelectedAsync(
        FileTranscriptionExportFormat format,
        CancellationToken cancellationToken)
    {
        if (SelectedJob is null || exportService is null) return null;
        try
        {
            var result = await exportService.ExportAsync(
                SelectedJob,
                format,
                cancellationToken);
            if (result == FileTranscriptionExportResult.Saved)
            {
                SetFeedback("FileTranscriptionFeedbackExported");
            }
            return result;
        }
        catch (FileTranscriptionExportException)
        {
            SetFeedback("FileTranscriptionFeedbackExportFailed", isError: true);
            return null;
        }
    }

    public async ValueTask<FileTranscriptionTranslationResult> TranslateSelectedAsync(
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        if (SelectedJob is null || translationService is null)
        {
            return FileTranscriptionTranslationResult.Unavailable;
        }
        IsTranslationRequestRunning = true;
        try
        {
            var result = await translationService.TranslateAsync(
                SelectedJob.Id,
                targetLanguage,
                cancellationToken);
            Refresh();
            SetFeedback(result == FileTranscriptionTranslationResult.Succeeded
                ? "FileTranscriptionFeedbackTranslated"
                : "FileTranscriptionFeedbackTranslationFailed",
                isError: result != FileTranscriptionTranslationResult.Succeeded);
            return result;
        }
        finally
        {
            IsTranslationRequestRunning = false;
        }
    }

    public async ValueTask<FileTranscriptionPlaybackResult> TogglePlaybackSelectedAsync(
        CancellationToken cancellationToken)
    {
        if (SelectedJob is null || playbackService is null)
        {
            return new FileTranscriptionPlaybackResult(
                FileTranscriptionPlaybackState.Failed);
        }

        SetFeedback("FileTranscriptionFeedbackPlaybackPreparing");
        var result = await playbackService.ToggleAsync(SelectedJob, cancellationToken);
        if (result.State == FileTranscriptionPlaybackState.Failed)
        {
            playbackJobId = null;
            SetFeedback("FileTranscriptionFeedbackPlaybackFailed", isError: true);
        }
        else
        {
            playbackJobId = SelectedJob.Id;
            playbackState = result.State;
            SetFeedback(result.State == FileTranscriptionPlaybackState.Paused
                ? "FileTranscriptionFeedbackPlaybackPaused"
                : "FileTranscriptionFeedbackPlaybackStarted");
        }
        OnPropertyChanged(nameof(IsSelectedPlaying));
        OnPropertyChanged(nameof(PlaybackLabel));
        return result;
    }

    public void Refresh()
    {
        if (jobs is null) return;
        var selectedId = SelectedJob?.Id;
        var latest = jobs.List();
        for (var index = 0; index < latest.Count; index++)
        {
            var job = latest[index];
            var presentation = CreatePresentation(job);
            if (index >= Jobs.Count)
            {
                Jobs.Add(job);
                JobItems.Add(presentation);
            }
            else if (!Equals(Jobs[index], job)
                || !JobItems[index].Diagnostics.SequenceEqual(presentation.Diagnostics))
            {
                Jobs[index] = job;
                JobItems[index] = presentation;
            }
        }
        while (Jobs.Count > latest.Count)
        {
            Jobs.RemoveAt(Jobs.Count - 1);
            JobItems.RemoveAt(JobItems.Count - 1);
        }
        SelectedItem = JobItems.FirstOrDefault(item => item.Id == selectedId)
            ?? JobItems.FirstOrDefault();
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(HasRunningJob));
        OnPropertyChanged(nameof(RunningProgressPercent));
        OnPropertyChanged(nameof(JobCountSummary));
        stateRefresh?.Invoke();
    }

    private FileTranscriptionJobPresentation CreatePresentation(FileTranscriptionJob job) => new(
        job,
        segments?.ListByJob(job.Id) ?? []);

    private bool ApplyLifecycle(
        Func<FileTranscriptionJobPresentation, bool> canApply,
        Func<string, bool> action,
        string feedbackKey)
    {
        if (SelectedItem is not { } item || !canApply(item) || !action(item.Id))
        {
            return false;
        }
        SetFeedback(feedbackKey);
        Refresh();
        return true;
    }

    private void SetFeedback(string key, bool isError = false)
    {
        if (isError)
        {
            LastError = L10n.Localize(key);
            LastActionMessage = null;
        }
        else
        {
            LastError = null;
            LastActionMessage = L10n.Localize(key);
        }
        OnPropertyChanged(nameof(Status));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
