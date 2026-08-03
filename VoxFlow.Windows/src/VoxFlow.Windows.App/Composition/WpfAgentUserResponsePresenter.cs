using System.Windows;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;

namespace VoxFlow.Windows.App.Composition;

/// <summary>Queues a non-blocking, user-facing Agent status notification on
/// the WPF dispatcher. It deliberately does not claim that any other tool has
/// completed a desktop side effect.</summary>
internal sealed class WpfAgentUserResponsePresenter : IAgentUserResponsePresenter
{
    public Task PresentAsync(AgentUserResponse response, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null) return Task.CompletedTask;
        _ = dispatcher.InvokeAsync(() => VoxFlowDialogWindow.ShowMessage(
            System.Windows.Application.Current?.MainWindow,
            L10n.Localize("AgentQuestionWindowTitle"),
            response.Text,
            response.Severity is AgentUserResponseSeverity.Warning or AgentUserResponseSeverity.Error
                ? VoxFlowDialogKind.Warning
                : VoxFlowDialogKind.Information));
        return Task.CompletedTask;
    }
}
