#if DEBUG
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Shell;

public sealed class DebugTranscriptInjectionViewModel : BindableObject
{
    private readonly Func<
        string,
        DebugTranscriptInjectionMode,
        CancellationToken,
        Task<DebugTranscriptInjectionResult>> run;
    private string transcript;
    private string selectedModeId = "agentCompose";
    private bool isBusy;
    private string? feedbackMessage;

    public DebugTranscriptInjectionViewModel(
        Func<
            string,
            DebugTranscriptInjectionMode,
            CancellationToken,
            Task<DebugTranscriptInjectionResult>> run)
    {
        this.run = run ?? throw new ArgumentNullException(nameof(run));
        transcript = L10n.Localize("DebugTranscriptInjectionDefaultText");
        Modes =
        [
            new("dictation", L10n.Localize("DebugTranscriptInjectionModeDictation")),
            new("agentCompose", L10n.Localize("DebugTranscriptInjectionModeAgentCompose")),
        ];
    }

    public string Heading => L10n.Localize("DebugTranscriptInjectionTitle");

    public string Subtitle => L10n.Localize("DebugTranscriptInjectionSubtitle");

    public string RunLabel => L10n.Localize("DebugTranscriptInjectionRun");

    public string Placeholder => L10n.Localize("DebugTranscriptInjectionPlaceholder");

    public IReadOnlyList<SettingsChoiceViewModel> Modes { get; }

    public string Transcript
    {
        get => transcript;
        set
        {
            SetField(ref transcript, value ?? string.Empty);
            OnPropertyChanged(nameof(CanRun));
        }
    }

    public string SelectedModeId
    {
        get => selectedModeId;
        set
        {
            if (value is not ("dictation" or "agentCompose"))
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }
            SetField(ref selectedModeId, value);
        }
    }

    public bool IsBusy
    {
        get => isBusy;
        private set
        {
            if (SetField(ref isBusy, value))
            {
                OnPropertyChanged(nameof(CanRun));
            }
        }
    }

    public bool CanRun => !IsBusy && !string.IsNullOrWhiteSpace(Transcript);

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public async Task<bool> RunAsync(CancellationToken cancellationToken)
    {
        if (!CanRun)
        {
            return false;
        }

        IsBusy = true;
        FeedbackMessage = L10n.Localize("DebugTranscriptInjectionRunning");
        try
        {
            var result = await run(
                Transcript.Trim(),
                SelectedModeId == "dictation"
                    ? DebugTranscriptInjectionMode.Dictation
                    : DebugTranscriptInjectionMode.AgentCompose,
                cancellationToken);
            FeedbackMessage = L10n.Localize(result.Status switch
            {
                DebugTranscriptInjectionStatus.Completed =>
                    "DebugTranscriptInjectionCompleted",
                DebugTranscriptInjectionStatus.Busy =>
                    "DebugTranscriptInjectionBusy",
                DebugTranscriptInjectionStatus.Unavailable =>
                    "DebugTranscriptInjectionUnavailable",
                _ => "DebugTranscriptInjectionFailed",
            });
            return result.Status == DebugTranscriptInjectionStatus.Completed;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            FeedbackMessage = L10n.Localize("DebugTranscriptInjectionFailed");
            throw;
        }
        catch
        {
            FeedbackMessage = L10n.Localize("DebugTranscriptInjectionFailed");
            return false;
        }
        finally
        {
            IsBusy = false;
        }
    }
}
#endif
