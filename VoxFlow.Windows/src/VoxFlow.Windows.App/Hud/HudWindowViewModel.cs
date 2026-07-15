using System.ComponentModel;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.App.Localization;
using System.Windows.Input;

namespace VoxFlow.Windows.App.Hud;

public sealed class HudWindowViewModel : INotifyPropertyChanged
{
    private HudPresentationSnapshot snapshot = HudPresentationMapper.Map(
        Application.Dictation.DictationSnapshot.Idle,
        HudLiveContext.Empty);
    private bool capsLockIndicatorEnabled;

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
        HudStatusChip.AgentReadingWindow => L10n.Localize("HudAgentReadingWindow"),
        HudStatusChip.AgentListening => L10n.Localize("HudAgentListening"),
        HudStatusChip.AgentTranscribing => L10n.Localize("HudAgentTranscribing"),
        HudStatusChip.AgentProcessing => L10n.Localize("HudAgentProcessing"),
        HudStatusChip.AgentOperating => L10n.Localize("HudAgentOperating"),
        HudStatusChip.AgentWaitingForUser => L10n.Localize("HudAgentWaitingForUser"),
        HudStatusChip.AgentCompleted => L10n.Localize("HudAgentCompleted"),
        HudStatusChip.AgentFailed => L10n.Localize("HudAgentFailed"),
        HudStatusChip.AgentCopied => L10n.Localize("HudAgentCopied"),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public bool ShowsText => !string.IsNullOrWhiteSpace(DisplayText);

    public bool ShowsWaveform => snapshot.ShowsWaveform;

    public bool ShowsSpinner => snapshot.ShowsSpinner;

    public bool ShowsCapsLockIndicator => capsLockIndicatorEnabled
        && snapshot.IsVisible
        && snapshot.StatusChip == HudStatusChip.Listening
        && Keyboard.IsKeyToggled(Key.CapsLock);

    public string CapsLockIndicatorText => L10n.Localize("HudCapsLock");

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
        OnPropertyChanged(nameof(ShowsCapsLockIndicator));
        OnPropertyChanged(nameof(Tone));
    }

    public void SetCapsLockIndicatorEnabled(bool enabled)
    {
        if (capsLockIndicatorEnabled == enabled)
        {
            return;
        }
        capsLockIndicatorEnabled = enabled;
        OnPropertyChanged(nameof(ShowsCapsLockIndicator));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
