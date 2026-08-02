using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

/// <summary>Bridges the established UIA-first selection flow into Agent context.
/// It deliberately does not retain UIA objects or broaden the context surface.</summary>
public sealed class WindowsAgentContextReader : IAgentContextReader
{
    private readonly IUiAutomationSelectionProbeProvider provider;
    private readonly IUiAutomationSelectionReader selectionReader;

    public WindowsAgentContextReader(
        IUiAutomationSelectionProbeProvider provider,
        TimeProvider? timeProvider = null)
    {
        this.provider = provider ?? throw new ArgumentNullException(nameof(provider));
        selectionReader = new UiAutomationSelectionReader(
            provider,
            timeProvider ?? TimeProvider.System);
    }

    public Task<AgentContextReadResult> ReadAsync(
        ForegroundTargetSnapshot target,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var probe = provider.ReadFocusedElement(target);
        if (probe is null)
        {
            return Task.FromResult(new AgentContextReadResult(null, null, null));
        }

        var chain = Enumerate(probe).ToArray();
        if (chain.Any(item => item.IsPassword))
        {
            return Task.FromResult(new AgentContextReadResult(null, null, null, IsSecure: true));
        }

        var selection = selectionReader.Read(target);
        var focusedInput = probe.FocusedInputText;
        var visible = chain
            .Select(item => item.VisibleText)
            .FirstOrDefault(text => !string.IsNullOrWhiteSpace(text));
        if (string.Equals(focusedInput, visible, StringComparison.Ordinal))
        {
            visible = null;
        }
        return Task.FromResult(new AgentContextReadResult(
            selection.Status == UiAutomationSelectionReadStatus.Captured
                ? selection.Snapshot
                : null,
            focusedInput,
            visible));
    }

    private static IEnumerable<UiAutomationElementProbe> Enumerate(
        UiAutomationElementProbe root)
    {
        for (var current = root; current is not null; current = current.Parent)
        {
            yield return current;
        }
    }
}
