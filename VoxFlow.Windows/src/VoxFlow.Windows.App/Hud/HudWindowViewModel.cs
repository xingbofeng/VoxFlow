using System.ComponentModel;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Hud;

public sealed class HudWindowViewModel : INotifyPropertyChanged
{
    private HudPresentationSnapshot snapshot = HudPresentationMapper.Map(
        Application.Dictation.DictationSnapshot.Idle,
        HudLiveContext.Empty);

    public event PropertyChangedEventHandler? PropertyChanged;

    public string? DisplayText => snapshot.Text ??
        (snapshot.Kind == HudPresentationKind.Failed
            ? OutputFailurePresentation.From(
                snapshot.ErrorCode ?? Domain.VoxFlowErrorCode.Unknown).Message
            : null);

    public string StatusText => snapshot.StatusChip switch
    {
        HudStatusChip.None => string.Empty,
        HudStatusChip.Preparing => L10n.Localize("HudPreparing"),
        HudStatusChip.Listening => L10n.Localize("HudListening"),
        HudStatusChip.Waiting => L10n.Localize("HudWaiting"),
        HudStatusChip.Improving => L10n.Localize("HudImproving"),
        HudStatusChip.Writing => L10n.Localize("HudWriting"),
        HudStatusChip.Completed => L10n.Localize("HudCompleted"),
        HudStatusChip.Failed => L10n.Localize("HudFailed"),
        HudStatusChip.Copied => L10n.Localize("HudCopied"),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public bool ShowsText => !string.IsNullOrWhiteSpace(DisplayText);

    public bool ShowsWaveform => snapshot.ShowsWaveform;

    public bool ShowsSpinner => snapshot.ShowsSpinner;

    public HudPresentationTone Tone => snapshot.Tone;

    public void Update(HudPresentationSnapshot value)
    {
        ArgumentNullException.ThrowIfNull(value);
        snapshot = value;
        OnPropertyChanged(nameof(DisplayText));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(ShowsText));
        OnPropertyChanged(nameof(ShowsWaveform));
        OnPropertyChanged(nameof(ShowsSpinner));
        OnPropertyChanged(nameof(Tone));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
