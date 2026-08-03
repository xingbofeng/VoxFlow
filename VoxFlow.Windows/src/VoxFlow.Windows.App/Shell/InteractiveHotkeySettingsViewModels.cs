using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Shell;

public sealed class InteractiveHotkeySettingsViewModel
{
    private readonly IInteractiveHotkeySettingsStore store;
    private readonly Action<InteractiveHotkeyBindingSet>? bindingsChanged;
    private readonly InteractiveHotkeyBindingEditor editor = new();
    private readonly SemaphoreSlim updateGate = new(1, 1);
    private InteractiveHotkeyBindingSet bindings = InteractiveHotkeyBindingSet.Default;

    public InteractiveHotkeySettingsViewModel(
        IInteractiveHotkeySettingsStore store,
        Action<InteractiveHotkeyBindingSet>? bindingsChanged = null)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.bindingsChanged = bindingsChanged;
        Dictation = new InteractiveHotkeyRowViewModel(
            this,
            InteractiveHotkeyAction.Dictation);
        Screenshot = new InteractiveHotkeyRowViewModel(
            this,
            InteractiveHotkeyAction.Screenshot);
        ClipboardImageOcr = new InteractiveHotkeyRowViewModel(
            this,
            InteractiveHotkeyAction.ClipboardImageOcr);
        Agent = new InteractiveHotkeyRowViewModel(
            this,
            InteractiveHotkeyAction.AgentCompose);
        AskAi = new InteractiveHotkeyRowViewModel(
            this,
            InteractiveHotkeyAction.SelectionAskAi);
        TranslationRows =
        [
            new InteractiveHotkeyRowViewModel(
                this,
                InteractiveHotkeyAction.SelectionTranslation),
            new InteractiveHotkeyRowViewModel(
                this,
                InteractiveHotkeyAction.SelectionSummary),
        ];
        AssistantRows =
        [
            TranslationRows[0],
            TranslationRows[1],
            Agent,
            AskAi,
        ];
    }

    public InteractiveHotkeyRowViewModel Screenshot { get; }

    public InteractiveHotkeyRowViewModel Dictation { get; }

    public InteractiveHotkeyRowViewModel ClipboardImageOcr { get; }

    public InteractiveHotkeyRowViewModel Agent { get; }

    public InteractiveHotkeyRowViewModel AskAi { get; }

    public IReadOnlyList<InteractiveHotkeyRowViewModel> TranslationRows { get; }

    public IReadOnlyList<InteractiveHotkeyRowViewModel> AssistantRows { get; }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        bindings = InteractiveHotkeyBindingSet.FromSettings(
            await store.LoadAsync(cancellationToken).ConfigureAwait(true));
        RefreshRows();
        bindingsChanged?.Invoke(bindings);
    }

    public async Task ResetAllToDefaultsAsync(CancellationToken cancellationToken)
    {
        await updateGate.WaitAsync(cancellationToken).ConfigureAwait(true);
        try
        {
            var defaults = InteractiveHotkeyBindingSet.Default;
            await store.SaveAsync(defaults.ToSettings(), cancellationToken)
                .ConfigureAwait(true);
            bindings = defaults;
            RefreshRows();
            bindingsChanged?.Invoke(bindings);
        }
        finally
        {
            updateGate.Release();
        }
    }

    internal HotkeyBinding? Binding(InteractiveHotkeyAction action) =>
        bindings.Get(action);

    internal HotkeyBinding? DefaultBinding(InteractiveHotkeyAction action) =>
        InteractiveHotkeyBindingSet.Default.Get(action);

    internal async Task<bool> ApplyAsync(
        InteractiveHotkeyRowViewModel row,
        HotkeyBinding? binding,
        CancellationToken cancellationToken)
    {
        await updateGate.WaitAsync(cancellationToken).ConfigureAwait(true);
        try
        {
            var result = editor.TrySet(bindings, row.Action, binding);
            if (result.Status != HotkeyCaptureStatus.Accepted)
            {
                row.SetConflict(result.Conflict, result.MessageKey);
                return false;
            }

            await store.SaveAsync(
                result.Bindings.ToSettings(),
                cancellationToken).ConfigureAwait(true);
            bindings = result.Bindings;
            RefreshRows();
            bindingsChanged?.Invoke(bindings);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            row.SetActionFailure();
            return false;
        }
        finally
        {
            updateGate.Release();
        }
    }

    internal Task<bool> RestoreDefaultAsync(
        InteractiveHotkeyRowViewModel row,
        CancellationToken cancellationToken) => ApplyAsync(
        row,
        InteractiveHotkeyBindingSet.Default.Get(row.Action),
        cancellationToken);

    private void RefreshRows()
    {
        Dictation.RefreshBinding();
        Screenshot.RefreshBinding();
        ClipboardImageOcr.RefreshBinding();
        Agent.RefreshBinding();
        AskAi.RefreshBinding();
        foreach (var row in TranslationRows)
        {
            row.RefreshBinding();
        }
    }
}

public sealed class InteractiveHotkeyRowViewModel : BindableObject
{
    private readonly InteractiveHotkeySettingsViewModel owner;
    private bool isRecording;
    private HotkeyConflictKind conflict;
    private string? conflictMessageKey;
    private string? actionFeedback;

    internal InteractiveHotkeyRowViewModel(
        InteractiveHotkeySettingsViewModel owner,
        InteractiveHotkeyAction action)
    {
        this.owner = owner;
        Action = action;
    }

    public InteractiveHotkeyAction Action { get; }

    public string Title => Action switch
    {
        InteractiveHotkeyAction.Dictation =>
            L10n.Localize("SettingsVoiceDictationTitle"),
        InteractiveHotkeyAction.Screenshot =>
            L10n.Localize("SettingsHotkeyScreenshotTitle"),
        InteractiveHotkeyAction.ClipboardImageOcr =>
            L10n.Localize("SettingsHotkeyClipboardImageOcrTitle"),
        InteractiveHotkeyAction.SelectionTranslation =>
            L10n.Localize("SettingsHotkeySelectionTranslationTitle"),
        InteractiveHotkeyAction.SelectionSummary =>
            L10n.Localize("SettingsHotkeySelectionSummaryTitle"),
        InteractiveHotkeyAction.AgentCompose =>
            L10n.Localize("SettingsHotkeyAgentComposeTitle"),
        InteractiveHotkeyAction.SelectionAskAi =>
            L10n.Localize("SettingsHotkeySelectionAskAiTitle"),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public string Description => Action switch
    {
        InteractiveHotkeyAction.Dictation =>
            L10n.Localize("SettingsVoiceDictationDescription"),
        InteractiveHotkeyAction.Screenshot =>
            L10n.Localize("SettingsHotkeyScreenshotDescription"),
        InteractiveHotkeyAction.ClipboardImageOcr =>
            L10n.Localize("SettingsHotkeyClipboardImageOcrDescription"),
        InteractiveHotkeyAction.SelectionTranslation =>
            L10n.Localize("SettingsHotkeySelectionTranslationDescription"),
        InteractiveHotkeyAction.SelectionSummary =>
            L10n.Localize("SettingsHotkeySelectionSummaryDescription"),
        InteractiveHotkeyAction.AgentCompose =>
            L10n.Localize("SettingsHotkeyAgentComposeDescription"),
        InteractiveHotkeyAction.SelectionAskAi =>
            L10n.Localize("SettingsHotkeySelectionAskAiDescription"),
        _ => throw new ArgumentOutOfRangeException(),
    };

    public HotkeyBinding? Binding => owner.Binding(Action);

    public bool IsBound => Binding is not null;

    public string BindingDisplay => Binding?.ToDisplayString()
        ?? L10n.Localize("SettingsHotkeyUnbound");

    /// <summary>Individual key chips for Mac-style badge row (Ctrl / Alt / Shift / A).</summary>
    public IReadOnlyList<string> BindingTokens => Binding is null
        ? []
        : Binding.ToDisplayTokens();

    public bool ShowsUnboundLabel => !IsRecording && !IsBound;

    public bool ShowsIdleActions => !IsRecording;

    public bool ShowsClearButton => !IsRecording && IsBound;

    public string StatusDisplay => IsRecording
        ? L10n.Localize("SettingsHotkeyRecordingStatus")
        : BindingDisplay;

    public bool CanRecord => !IsRecording;

    public bool CanCancel => IsRecording;

    public bool CanClear => !IsRecording
        && IsBound
        && Action != InteractiveHotkeyAction.Dictation;

    public bool CanRestoreDefault =>
        !IsRecording && Binding != owner.DefaultBinding(Action);

    public string? ActionFeedback
    {
        get => actionFeedback;
        private set => SetField(ref actionFeedback, value);
    }

    public bool IsRecording
    {
        get => isRecording;
        private set
        {
            if (SetField(ref isRecording, value))
            {
                OnPropertyChanged(nameof(StatusDisplay));
                OnPropertyChanged(nameof(ShowsIdleActions));
                OnPropertyChanged(nameof(ShowsUnboundLabel));
                OnPropertyChanged(nameof(ShowsClearButton));
                NotifyActionAvailabilityChanged();
            }
        }
    }

    public HotkeyConflictKind Conflict
    {
        get => conflict;
        private set => SetField(ref conflict, value);
    }

    public bool HasConflict => Conflict != HotkeyConflictKind.None;

    public bool ShowsAltGrRisk => Conflict == HotkeyConflictKind.AltGrUnsafe;

    public string? ConflictMessageKey
    {
        get => conflictMessageKey;
        private set => SetField(ref conflictMessageKey, value);
    }

    public string? ConflictMessage => ConflictMessageKey is null
        ? null
        : L10n.Localize(ConflictMessageKey);

    public void BeginRecording()
    {
        ClearConflict();
        ActionFeedback = null;
        IsRecording = true;
    }

    public void CancelRecording()
    {
        ActionFeedback = null;
        IsRecording = false;
    }

    internal void RejectAltGrCapture()
    {
        IsRecording = false;
        SetConflict(
            HotkeyConflictKind.AltGrUnsafe,
            "hotkey.conflict.altGrUnsafe");
    }

    public async Task<bool> ApplyCapturedBindingAsync(
        HotkeyBinding binding,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(binding);
        IsRecording = false;
        return await owner.ApplyAsync(this, binding, cancellationToken)
            .ConfigureAwait(true);
    }

    public Task<bool> ClearAsync(CancellationToken cancellationToken)
    {
        IsRecording = false;
        return owner.ApplyAsync(this, binding: null, cancellationToken);
    }

    public Task<bool> RestoreDefaultAsync(CancellationToken cancellationToken)
    {
        IsRecording = false;
        return owner.RestoreDefaultAsync(this, cancellationToken);
    }

    internal void SetConflict(
        HotkeyConflictKind value,
        string? messageKey)
    {
        ActionFeedback = null;
        Conflict = value;
        ConflictMessageKey = messageKey;
        OnPropertyChanged(nameof(HasConflict));
        OnPropertyChanged(nameof(ShowsAltGrRisk));
        OnPropertyChanged(nameof(ConflictMessage));
    }

    internal void RefreshBinding()
    {
        ClearConflict();
        ActionFeedback = null;
        OnPropertyChanged(nameof(Binding));
        OnPropertyChanged(nameof(IsBound));
        OnPropertyChanged(nameof(BindingDisplay));
        OnPropertyChanged(nameof(BindingTokens));
        OnPropertyChanged(nameof(ShowsUnboundLabel));
        OnPropertyChanged(nameof(ShowsIdleActions));
        OnPropertyChanged(nameof(ShowsClearButton));
        OnPropertyChanged(nameof(StatusDisplay));
        NotifyActionAvailabilityChanged();
    }

    internal void SetActionFailure()
    {
        ClearConflict();
        ActionFeedback = L10n.Localize("SettingsOperationFailed");
    }

    private void NotifyActionAvailabilityChanged()
    {
        OnPropertyChanged(nameof(CanRecord));
        OnPropertyChanged(nameof(CanCancel));
        OnPropertyChanged(nameof(CanClear));
        OnPropertyChanged(nameof(CanRestoreDefault));
    }

    private void ClearConflict() => SetConflict(
        HotkeyConflictKind.None,
        messageKey: null);
}
