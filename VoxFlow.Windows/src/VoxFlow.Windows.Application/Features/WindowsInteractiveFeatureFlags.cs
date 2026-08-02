using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Features;

public sealed class WindowsInteractiveFeatureFlags
{
    public WindowsInteractiveFeatureFlags(
        bool selectionTransformEnabled = false,
        bool builtinAgentEnabled = false)
    {
        SelectionTransformEnabled = selectionTransformEnabled;
        BuiltinAgentEnabled = builtinAgentEnabled;
    }

    public static WindowsInteractiveFeatureFlags Disabled { get; } = new();

    public bool SelectionTransformEnabled { get; }

    public bool BuiltinAgentEnabled { get; }

    public bool AnyEnabled => SelectionTransformEnabled || BuiltinAgentEnabled;
}

public sealed class InteractiveFeatureRegistrationPlan
{
    private InteractiveFeatureRegistrationPlan(
        WindowsInteractiveFeatureFlags flags,
        IReadOnlyList<InteractiveWorkflowKind> workflowKinds,
        IReadOnlyList<string> hotkeyActionIds,
        IReadOnlyList<string> trayCommandIds)
    {
        Flags = flags;
        WorkflowKinds = workflowKinds;
        HotkeyActionIds = hotkeyActionIds;
        TrayCommandIds = trayCommandIds;
    }

    public WindowsInteractiveFeatureFlags Flags { get; }

    public IReadOnlyList<InteractiveWorkflowKind> WorkflowKinds { get; }

    public IReadOnlyList<string> HotkeyActionIds { get; }

    public IReadOnlyList<string> TrayCommandIds { get; }

    public bool RequiresWorkflowDatabase => Flags.AnyEnabled;

    public static InteractiveFeatureRegistrationPlan Create(
        WindowsInteractiveFeatureFlags flags)
    {
        ArgumentNullException.ThrowIfNull(flags);
        List<InteractiveWorkflowKind> workflowKinds = [];
        List<string> hotkeyActionIds = [];
        List<string> trayCommandIds = [];

        if (flags.SelectionTransformEnabled)
        {
            workflowKinds.Add(InteractiveWorkflowKind.SelectionTranslation);
            workflowKinds.Add(InteractiveWorkflowKind.SelectionSummary);
            hotkeyActionIds.Add("selection.translate");
            hotkeyActionIds.Add("selection.summary");
            trayCommandIds.Add("selection.translate");
            trayCommandIds.Add("selection.summary");
        }

        if (flags.BuiltinAgentEnabled)
        {
            workflowKinds.Add(InteractiveWorkflowKind.AgentCompose);
            hotkeyActionIds.Add("agent.compose");
            trayCommandIds.Add("agent.compose");
        }

        return new InteractiveFeatureRegistrationPlan(
            flags,
            Array.AsReadOnly(workflowKinds.ToArray()),
            Array.AsReadOnly(hotkeyActionIds.ToArray()),
            Array.AsReadOnly(trayCommandIds.ToArray()));
    }
}

/// <summary>
/// Prevents disabled feature factories from being evaluated at all. This keeps
/// sidecar, UI Automation, OCR, and new hotkey dependencies out of the default
/// P1/P3 process graph until their vertical slices are ready.
/// </summary>
public sealed class InteractiveFeatureDependencyGate
{
    public InteractiveFeatureDependencyGate(WindowsInteractiveFeatureFlags flags)
    {
        Flags = flags ?? throw new ArgumentNullException(nameof(flags));
        Plan = InteractiveFeatureRegistrationPlan.Create(flags);
    }

    public WindowsInteractiveFeatureFlags Flags { get; }

    public InteractiveFeatureRegistrationPlan Plan { get; }

    public T? CreateSelectionDependency<T>(Func<T> factory) where T : class
    {
        ArgumentNullException.ThrowIfNull(factory);
        return Flags.SelectionTransformEnabled ? factory() : null;
    }

    public T? CreateAgentDependency<T>(Func<T> factory) where T : class
    {
        ArgumentNullException.ThrowIfNull(factory);
        return Flags.BuiltinAgentEnabled ? factory() : null;
    }
}
