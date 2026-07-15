using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Output;

/// <summary>Writes only through a freshly revalidated, frozen UIA selection.
/// Insert collapses the verified range at its end before pasting; it never
/// emits Enter or retargets the current foreground window.</summary>
public sealed class WindowsAgentTextFieldGatewayFactory(
    WindowsClipboardGateway clipboard) : IAgentTextFieldGatewayFactory
{
    private readonly WindowsClipboardGateway clipboard = clipboard
        ?? throw new ArgumentNullException(nameof(clipboard));

    public IAgentTextFieldGateway Create(SelectionSnapshot? selection) =>
        new Gateway(selection, clipboard);

    private sealed class Gateway(
        SelectionSnapshot? selection,
        WindowsClipboardGateway clipboard) : IAgentTextFieldGateway
    {
        private readonly ISelectionTargetActivation activation = new Win32SelectionTargetActivation();
        private readonly IWin32ForegroundSelectionApi foreground = new WindowsForegroundSelectionApi();

        public Task<AgentTextFieldWriteStatus> ReplaceSelectionAsync(
            string text,
            CancellationToken cancellationToken) => WriteAsync(text, collapseToEnd: false, cancellationToken);

        public Task<AgentTextFieldWriteStatus> InsertAsync(
            string text,
            CancellationToken cancellationToken) => WriteAsync(text, collapseToEnd: true, cancellationToken);

        private async Task<AgentTextFieldWriteStatus> WriteAsync(
            string text,
            bool collapseToEnd,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (selection is null)
            {
                return CopyFallback(text, AgentTextFieldWriteStatus.MissingSelection);
            }
            if (!selection.IsEditable || !selection.AllowsReselection)
            {
                return CopyFallback(text, AgentTextFieldWriteStatus.ReadOnly);
            }
            if (!activation.Activate(selection.Target) || !activation.IsStillTarget(selection.Target))
            {
                return CopyFallback(text, AgentTextFieldWriteStatus.TargetChanged);
            }

            var revalidator = new SelectionTargetRevalidator(
                new WindowsUiAutomationSelectionRevalidationProbeProvider(foreground),
                new WindowsUiAutomationRangeReselector(foreground));
            var verification = revalidator.RevalidateAndReselect(selection);
            if (!verification.CanWrite)
            {
                return CopyFallback(text, Map(verification.Status));
            }
            if (!activation.IsStillTarget(selection.Target))
            {
                return CopyFallback(text, AgentTextFieldWriteStatus.TargetChanged);
            }
            if (collapseToEnd
                && !new WindowsSafeKeyboardInputSender().Press(["Right"]))
            {
                return CopyFallback(text, AgentTextFieldWriteStatus.InputFailed);
            }
            if (!activation.IsStillTarget(selection.Target))
            {
                return CopyFallback(text, AgentTextFieldWriteStatus.TargetChanged);
            }

            var output = new QuickPasteService(clipboard, new WindowsPasteShortcutSender());
            var result = await output.PasteAsync(text, cancellationToken).ConfigureAwait(false);
            return result.Kind == OutputResultKind.Inserted
                ? AgentTextFieldWriteStatus.Succeeded
                : result.Kind == OutputResultKind.PermissionDenied
                    ? CopyFallback(text, AgentTextFieldWriteStatus.UipiBlocked)
                    : CopyFallback(text, AgentTextFieldWriteStatus.InputFailed);
        }

        private AgentTextFieldWriteStatus CopyFallback(
            string text,
            AgentTextFieldWriteStatus status)
        {
            try
            {
                _ = clipboard.WriteUnicodeText(text);
            }
            catch (ClipboardOperationException)
            {
                // Preserve the truthful write failure even if recovery copy is busy.
            }
            return status;
        }

        private static AgentTextFieldWriteStatus Map(
            SelectionTargetRevalidationStatus status) => status switch
        {
            SelectionTargetRevalidationStatus.NotEditable => AgentTextFieldWriteStatus.ReadOnly,
            SelectionTargetRevalidationStatus.SecureTarget => AgentTextFieldWriteStatus.Secure,
            SelectionTargetRevalidationStatus.HigherIntegrityBlocked
                or SelectionTargetRevalidationStatus.UipiBlocked => AgentTextFieldWriteStatus.UipiBlocked,
            SelectionTargetRevalidationStatus.TargetClosed
                or SelectionTargetRevalidationStatus.TargetChanged
                or SelectionTargetRevalidationStatus.IntegrityLevelChanged => AgentTextFieldWriteStatus.TargetChanged,
            _ => AgentTextFieldWriteStatus.InputFailed,
        };
    }
}
