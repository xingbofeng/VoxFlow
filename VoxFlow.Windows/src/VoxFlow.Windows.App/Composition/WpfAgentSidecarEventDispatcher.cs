using System.Windows.Threading;
using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.App.Composition;

/// <summary>Marshals sidecar-driven presentation callbacks to the WPF UI
/// thread. The JSONL reader only schedules this work and continues reading.</summary>
internal sealed class WpfAgentSidecarEventDispatcher : IAgentSidecarEventDispatcher
{
    public Task DispatchAsync(Func<Task> action, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        return dispatcher is null
            ? action()
            : dispatcher.InvokeAsync(action, DispatcherPriority.Normal, cancellationToken).Task.Unwrap();
    }
}
