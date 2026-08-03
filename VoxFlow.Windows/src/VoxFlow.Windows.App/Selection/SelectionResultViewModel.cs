using System.ComponentModel;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.SelectionTransform;

namespace VoxFlow.Windows.App.Selection;

public enum SelectionResultTab
{
    Source,
    Result,
}

public enum SelectionTransformPresentationState
{
    Idle,
    Running,
    Completed,
    PartiallyCompleted,
    Failed,
    Cancelled,
}

public sealed record SelectionTransformHistoryRecord(
    SelectionTransformOperation Operation,
    string SourceText,
    string Text,
    SelectionTransformPresentationState State,
    string? SafeFailureMessage);

public interface ISelectionTransformHistoryRecorder
{
    void Record(SelectionTransformHistoryRecord record);
}

public interface ISelectionResultClipboard
{
    bool TrySetText(string text);
}

public interface ISelectionResultWriter
{
    Task<bool> ReplaceAsync(string text, CancellationToken cancellationToken);

    Task<bool> InsertAfterAsync(string text, CancellationToken cancellationToken);
}

public sealed class NoopSelectionTransformHistoryRecorder : ISelectionTransformHistoryRecorder
{
    public void Record(SelectionTransformHistoryRecord record)
    {
    }
}

/// <summary>
/// Presentation-only owner for a single selection result panel. It makes the
/// cancellation and single-history-write rules explicit, so selecting Source,
/// pressing Escape, closing, and superseding an operation all have identical
/// terminal behavior.
/// </summary>
public sealed class SelectionResultViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly ISelectionTransformStreamingService service;
    private readonly ISelectionTransformHistoryRecorder history;
    private readonly ISelectionResultClipboard? clipboard;
    private readonly ISelectionResultWriter? writer;
    private CancellationTokenSource? cancellation;
    private Guid generation;
    private bool historyRecorded;
    private SelectionResultTab selectedTab = SelectionResultTab.Result;
    private string resultText = string.Empty;
    private bool isTransforming;
    private bool isActionBusy;
    private bool isSpeaking;
    private SelectionTransformPresentationState state;
    private string? statusMessage;
    private bool disposed;

    public SelectionResultViewModel(
        string selectedText,
        SelectionTransformOperation operation,
        ISelectionTransformStreamingService service,
        ISelectionTransformHistoryRecorder? history = null,
        ISelectionResultClipboard? clipboard = null,
        ISelectionResultWriter? writer = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(selectedText);
        if (!Enum.IsDefined(operation))
        {
            throw new ArgumentOutOfRangeException(nameof(operation));
        }

        SelectedText = selectedText;
        Operation = operation;
        this.service = service ?? throw new ArgumentNullException(nameof(service));
        this.history = history ?? new NoopSelectionTransformHistoryRecorder();
        this.clipboard = clipboard;
        this.writer = writer;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string SelectedText { get; }

    public SelectionTransformOperation Operation { get; }

    public string OperationLabel => Operation switch
    {
        SelectionTransformOperation.Translation => L10n.SelectionResultTranslation,
        SelectionTransformOperation.Summary => L10n.SelectionResultSummary,
        SelectionTransformOperation.Refine => L10n.Localize("SelectionResultRefine"),
        SelectionTransformOperation.AskAi => L10n.Localize("SelectionResultAskAi"),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public SelectionResultTab SelectedTab
    {
        get => selectedTab;
        private set => SetField(ref selectedTab, value);
    }

    public string ResultText
    {
        get => resultText;
        private set
        {
            if (SetField(ref resultText, value))
            {
                OnPropertyChanged(nameof(DisplayedText));
                NotifyActionAvailability();
            }
        }
    }

    public string DisplayedText => SelectedTab == SelectionResultTab.Source
        ? SelectedText
        : ResultText;

    public bool IsSourceTab => SelectedTab == SelectionResultTab.Source;

    public bool IsResultTab => SelectedTab == SelectionResultTab.Result;

    public bool CanCopy => clipboard is not null
        && !IsActionBusy
        && !string.IsNullOrWhiteSpace(DisplayedText);

    public bool CanSpeak => !IsActionBusy
        && !string.IsNullOrWhiteSpace(DisplayedText);

    public bool CanWriteBack => writer is not null
        && !IsActionBusy
        && !string.IsNullOrWhiteSpace(DisplayedText);

    public bool IsSpeaking
    {
        get => isSpeaking;
        private set
        {
            if (SetField(ref isSpeaking, value))
            {
                OnPropertyChanged(nameof(SpeakButtonLabel));
            }
        }
    }

    public string SpeakButtonLabel => IsSpeaking
        ? L10n.SelectionResultStopSpeaking
        : L10n.SelectionResultSpeak;

    public string StatusText => StatusMessage switch
    {
        "no_text" => L10n.Localize("SelectionResultNoText"),
        "copy_failed" => L10n.Localize("SelectionResultCopyFailed"),
        "copied" => L10n.Localize("SelectionResultCopied"),
        "write_unavailable" => L10n.Localize("SelectionResultWriteUnavailable"),
        "replaced" => L10n.Localize("SelectionResultReplaced"),
        "inserted" => L10n.Localize("SelectionResultInserted"),
        "copied_fallback" => L10n.Localize("SelectionResultCopiedFallback"),
        "write_failed" => L10n.Localize("SelectionResultWriteFailed"),
        "cancelled" => L10n.Localize("SelectionResultCancelled"),
        "transform_failed" => L10n.Localize("SelectionResultFailed"),
        "speaking" => L10n.Localize("SelectionResultSpeaking"),
        "speech_complete" => L10n.Localize("SelectionResultSpeechComplete"),
        "speech_stopped" => L10n.Localize("SelectionResultSpeechStopped"),
        "speech_unavailable" => L10n.Localize("SelectionResultSpeechUnavailable"),
        "speech_failed" => L10n.Localize("SelectionResultSpeechFailed"),
        _ => State switch
        {
            SelectionTransformPresentationState.Running => L10n.SelectionResultProcessing,
            SelectionTransformPresentationState.Completed =>
                L10n.Localize("SelectionResultComplete"),
            SelectionTransformPresentationState.PartiallyCompleted =>
                L10n.Localize("SelectionResultPartial"),
            SelectionTransformPresentationState.Cancelled =>
                L10n.Localize("SelectionResultCancelled"),
            SelectionTransformPresentationState.Failed =>
                L10n.Localize("SelectionResultFailed"),
            _ => string.Empty,
        },
    };

    public bool IsTransforming
    {
        get => isTransforming;
        private set => SetField(ref isTransforming, value);
    }

    public bool IsActionBusy
    {
        get => isActionBusy;
        private set
        {
            if (SetField(ref isActionBusy, value))
            {
                NotifyActionAvailability();
            }
        }
    }

    public SelectionTransformPresentationState State
    {
        get => state;
        private set
        {
            if (SetField(ref state, value))
            {
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public string? StatusMessage
    {
        get => statusMessage;
        private set
        {
            if (SetField(ref statusMessage, value))
            {
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public void SelectTab(SelectionResultTab tab)
    {
        if (!Enum.IsDefined(tab))
        {
            throw new ArgumentOutOfRangeException(nameof(tab));
        }

        if (SelectedTab == tab)
        {
            return;
        }

        SelectedTab = tab;
        OnPropertyChanged(nameof(DisplayedText));
        OnPropertyChanged(nameof(IsSourceTab));
        OnPropertyChanged(nameof(IsResultTab));
        NotifyActionAvailability();
        if (tab == SelectionResultTab.Source)
        {
            CancelTransform();
        }
    }

    public async Task StartAsync()
    {
        ThrowIfDisposed();
        CancelTransform();
        generation = Guid.NewGuid();
        historyRecorded = false;
        ResultText = string.Empty;
        SelectedTab = SelectionResultTab.Result;
        OnPropertyChanged(nameof(DisplayedText));
        OnPropertyChanged(nameof(IsSourceTab));
        OnPropertyChanged(nameof(IsResultTab));
        NotifyActionAvailability();
        StatusMessage = null;
        State = SelectionTransformPresentationState.Running;
        IsTransforming = true;
        cancellation = new CancellationTokenSource();
        var currentGeneration = generation;
        var token = cancellation.Token;

        try
        {
            await foreach (var update in service.TransformAsync(
                               new SelectionTransformRequest(currentGeneration, SelectedText, Operation),
                               token)
                               .WithCancellation(token))
            {
                if (currentGeneration != generation || token.IsCancellationRequested)
                {
                    return;
                }

                Apply(update);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            // CancelTransform owns the terminal state and history record.
        }
        catch
        {
            if (currentGeneration == generation)
            {
                State = SelectionTransformPresentationState.Failed;
                StatusMessage = "transform_failed";
                RecordTerminalIfNonEmpty(State, "selection_transform_failed");
            }
        }
        finally
        {
            if (currentGeneration == generation)
            {
                IsTransforming = false;
                cancellation?.Dispose();
                cancellation = null;
            }
        }
    }

    public void CancelTransform()
    {
        if (!IsTransforming)
        {
            return;
        }

        generation = Guid.NewGuid();
        cancellation?.Cancel();
        cancellation?.Dispose();
        cancellation = null;
        IsTransforming = false;
        var hasPartialResult = !string.IsNullOrWhiteSpace(ResultText);
        State = hasPartialResult
            ? SelectionTransformPresentationState.PartiallyCompleted
            : SelectionTransformPresentationState.Cancelled;
        StatusMessage = hasPartialResult
            ? null
            : "cancelled";
        RecordTerminalIfNonEmpty(State, safeFailureMessage: null);
    }

    public void Close() => CancelTransform();

    public bool CopyDisplayedText()
    {
        var text = DisplayedText.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            StatusMessage = "no_text";
            return false;
        }
        try
        {
            if (clipboard is null || !clipboard.TrySetText(DisplayedText))
            {
                StatusMessage = "copy_failed";
                return false;
            }
        }
        catch
        {
            StatusMessage = "copy_failed";
            return false;
        }

        StatusMessage = "copied";
        return true;
    }

    public Task<bool> ReplaceDisplayedTextAsync(CancellationToken cancellationToken = default) =>
        WriteDisplayedTextAsync(replace: true, cancellationToken);

    public Task<bool> InsertAfterDisplayedTextAsync(CancellationToken cancellationToken = default) =>
        WriteDisplayedTextAsync(replace: false, cancellationToken);

    private async Task<bool> WriteDisplayedTextAsync(bool replace, CancellationToken cancellationToken)
    {
        var text = DisplayedText.Trim();
        if (writer is null || string.IsNullOrWhiteSpace(text))
        {
            StatusMessage = "write_unavailable";
            return false;
        }
        if (IsActionBusy)
        {
            return false;
        }

        IsActionBusy = true;
        try
        {
            var written = replace
                ? await writer.ReplaceAsync(DisplayedText, cancellationToken)
                : await writer.InsertAfterAsync(DisplayedText, cancellationToken);
            StatusMessage = written
                ? replace ? "replaced" : "inserted"
                : "copied_fallback";
            return written;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            StatusMessage = "cancelled";
            return false;
        }
        catch
        {
            StatusMessage = "write_failed";
            return false;
        }
        finally
        {
            IsActionBusy = false;
        }
    }

    public void ReportSpeechState(
        SelectionSpeechState speechState,
        bool userStopped = false)
    {
        IsSpeaking = speechState == SelectionSpeechState.Speaking;
        StatusMessage = userStopped
            ? "speech_stopped"
            : speechState switch
            {
                SelectionSpeechState.Idle => "speech_complete",
                SelectionSpeechState.Speaking => "speaking",
                SelectionSpeechState.Unavailable => "speech_unavailable",
                SelectionSpeechState.Failed => "speech_failed",
                _ => throw new ArgumentOutOfRangeException(nameof(speechState)),
            };
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        Close();
        cancellation?.Dispose();
    }

    private void Apply(SelectionTransformEvent update)
    {
        if (update.Generation != generation)
        {
            return;
        }
        switch (update)
        {
            case SelectionTransformStarted:
                State = SelectionTransformPresentationState.Running;
                break;
            case SelectionTransformPartial partial:
                ResultText = partial.Text;
                break;
            case SelectionTransformCompleted completed:
                ResultText = completed.Text;
                StatusMessage = null;
                State = SelectionTransformPresentationState.Completed;
                IsTransforming = false;
                RecordTerminalIfNonEmpty(State, null);
                break;
            case SelectionTransformCancelled cancelled:
                ResultText = cancelled.PartialText;
                var hasPartialResult = !string.IsNullOrWhiteSpace(ResultText);
                StatusMessage = hasPartialResult ? null : "cancelled";
                State = hasPartialResult
                    ? SelectionTransformPresentationState.PartiallyCompleted
                    : SelectionTransformPresentationState.Cancelled;
                IsTransforming = false;
                RecordTerminalIfNonEmpty(State, null);
                break;
            case SelectionTransformFailed failed:
                ResultText = failed.PartialText;
                State = SelectionTransformPresentationState.Failed;
                StatusMessage = "transform_failed";
                IsTransforming = false;
                RecordTerminalIfNonEmpty(State, failed.SafeMessage);
                break;
        }
    }

    private void RecordTerminalIfNonEmpty(
        SelectionTransformPresentationState terminalState,
        string? safeFailureMessage)
    {
        if (historyRecorded || string.IsNullOrWhiteSpace(ResultText))
        {
            return;
        }

        historyRecorded = true;
        history.Record(new SelectionTransformHistoryRecord(
            Operation,
            SelectedText,
            ResultText,
            terminalState,
            safeFailureMessage));
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void NotifyActionAvailability()
    {
        OnPropertyChanged(nameof(CanCopy));
        OnPropertyChanged(nameof(CanSpeak));
        OnPropertyChanged(nameof(CanWriteBack));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
    }
}
