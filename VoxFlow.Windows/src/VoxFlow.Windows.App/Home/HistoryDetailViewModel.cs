using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Home;

public sealed class HistoryDetailViewModel : INotifyPropertyChanged
{
    private string finalText;
    private string editedFinalText;

    internal HistoryDetailViewModel(HistoryEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        Id = entry.Id;
        RawText = entry.RawText;
        finalText = entry.FinalText;
        editedFinalText = entry.FinalText;
        CreatedAtUtc = entry.CreatedAtUtc;
        Recovered = entry.Metadata.Recovered;
        CapturedFrameCount = entry.Metadata.CapturedFrameCount;
        DroppedFrameCount = entry.Metadata.DroppedFrameCount;
        DurationMilliseconds = entry.Metadata.DurationMilliseconds;
        ErrorCode = entry.Metadata.ErrorCode;
        AsrProvider = entry.Metadata.AsrProvider;
        QwenVariant = entry.Metadata.QwenVariant;
        RecognitionLanguage = entry.Metadata.RecognitionLanguage;
        LlmProvider = entry.Metadata.LlmProvider;
        LlmDurationMilliseconds = entry.Metadata.LlmDurationMilliseconds;
        SanitizedDiagnostic = JsonSerializer.Serialize(
            new HistoryDiagnostic(
                SchemaVersion: 1,
                CreatedAtUtc,
                Recovered,
                CapturedFrameCount,
                DroppedFrameCount,
                DurationMilliseconds,
                ErrorCode,
                AsrProvider,
                QwenVariant,
                RecognitionLanguage,
                LlmProvider,
                LlmDurationMilliseconds),
            DomainJson.Options);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Id { get; }

    public string RawText { get; }

    public string FinalText
    {
        get => finalText;
        private set
        {
            if (finalText == value)
            {
                return;
            }

            finalText = value;
            OnPropertyChanged();
        }
    }

    public string EditedFinalText
    {
        get => editedFinalText;
        set
        {
            ArgumentNullException.ThrowIfNull(value);
            if (editedFinalText == value)
            {
                return;
            }

            editedFinalText = value;
            OnPropertyChanged();
        }
    }

    public DateTimeOffset CreatedAtUtc { get; }

    public bool Recovered { get; }

    public long CapturedFrameCount { get; }

    public long DroppedFrameCount { get; }

    public long? DurationMilliseconds { get; }

    public VoxFlowErrorCode? ErrorCode { get; }

    public AsrProviderId? AsrProvider { get; }

    public QwenVariant? QwenVariant { get; }

    public RecognitionLanguage? RecognitionLanguage { get; }

    public LlmProviderId? LlmProvider { get; }

    public long? LlmDurationMilliseconds { get; }

    public string SanitizedDiagnostic { get; }

    internal void ApplyFinalText(string value)
    {
        FinalText = value;
        EditedFinalText = value;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private sealed record HistoryDiagnostic(
        int SchemaVersion,
        DateTimeOffset CreatedAtUtc,
        bool Recovered,
        long CapturedFrameCount,
        long DroppedFrameCount,
        long? DurationMilliseconds,
        VoxFlowErrorCode? ErrorCode,
        AsrProviderId? AsrProvider,
        QwenVariant? QwenVariant,
        RecognitionLanguage? RecognitionLanguage,
        LlmProviderId? LlmProvider,
        long? LlmDurationMilliseconds);
}
