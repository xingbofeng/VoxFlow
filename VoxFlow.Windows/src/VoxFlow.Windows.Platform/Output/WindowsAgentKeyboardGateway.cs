using System.Diagnostics;
using System.Globalization;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Output;

/// <summary>Windows implementation of the Agent keyboard boundary. Every
/// operation rechecks the frozen target immediately before SendInput and
/// refuses higher-integrity targets rather than attempting elevation.</summary>
public sealed class WindowsAgentKeyboardGatewayFactory : IAgentKeyboardGatewayFactory
{
    private readonly IWin32ForegroundSelectionApi foreground;
    private readonly int processId;

    public WindowsAgentKeyboardGatewayFactory()
        : this(new WindowsForegroundSelectionApi(), Process.GetCurrentProcess().Id)
    {
    }

    internal WindowsAgentKeyboardGatewayFactory(
        IWin32ForegroundSelectionApi foreground,
        int processId)
    {
        this.foreground = foreground ?? throw new ArgumentNullException(nameof(foreground));
        if (processId <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(processId));
        }
        this.processId = processId;
    }

    public IAgentKeyboardGateway Create(ForegroundTargetSnapshot target) =>
        new Gateway(target, foreground, processId, new WindowsSafeKeyboardInputSender());

    private sealed class Gateway(
        ForegroundTargetSnapshot target,
        IWin32ForegroundSelectionApi foreground,
        int processId,
        WindowsSafeKeyboardInputSender input) : IAgentKeyboardGateway
    {
        public Task<AgentKeyboardWriteStatus> TypeAsync(
            string text,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var validation = ValidateTarget();
            if (validation != AgentKeyboardWriteStatus.Succeeded)
            {
                return Task.FromResult(validation);
            }
            return Task.FromResult(input.TypeText(text)
                ? AgentKeyboardWriteStatus.Succeeded
                : AgentKeyboardWriteStatus.InputFailed);
        }

        public Task<AgentKeyboardWriteStatus> PressAsync(
            IReadOnlyList<string> keys,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var validation = ValidateTarget();
            if (validation != AgentKeyboardWriteStatus.Succeeded)
            {
                return Task.FromResult(validation);
            }
            return Task.FromResult(input.Press(keys)
                ? AgentKeyboardWriteStatus.Succeeded
                : AgentKeyboardWriteStatus.InputFailed);
        }

        private AgentKeyboardWriteStatus ValidateTarget()
        {
            if (target.IntegrityLevel is ProcessIntegrityLevel.High
                or ProcessIntegrityLevel.System
                or ProcessIntegrityLevel.Protected)
            {
                return AgentKeyboardWriteStatus.UipiBlocked;
            }
            var current = foreground.ReadForeground();
            return current is not null
                && current.ProcessId == target.ProcessId
                && current.WindowHandle == target.WindowHandle
                && current.ProcessId != processId
                ? AgentKeyboardWriteStatus.Succeeded
                : AgentKeyboardWriteStatus.TargetChanged;
        }
    }
}

internal sealed class WindowsSafeKeyboardInputSender
{
    private static readonly IReadOnlyDictionary<string, ushort> VirtualKeys =
        new Dictionary<string, ushort>(StringComparer.OrdinalIgnoreCase)
        {
            ["Escape"] = 0x1B,
            ["Tab"] = 0x09,
            ["Backspace"] = 0x08,
            ["Delete"] = 0x2E,
            ["Left"] = 0x25,
            ["Up"] = 0x26,
            ["Right"] = 0x27,
            ["Down"] = 0x28,
            ["Home"] = 0x24,
            ["End"] = 0x23,
        };

    public bool TypeText(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        var starts = StringInfo.ParseCombiningCharacters(text);
        foreach (var start in starts)
        {
            var next = Array.IndexOf(starts, start) + 1;
            var end = next < starts.Length ? starts[next] : text.Length;
            var element = text[start..end];
            var encoded = UnicodeKeyboardEventEncoder.Encode(element);
            var inputs = new WindowsInputInterop.NativeInput[encoded.Count];
            for (var index = 0; index < encoded.Count; index++)
            {
                inputs[index] = WindowsInputInterop.CreateUnicode(
                    encoded[index].CodeUnit, encoded[index].IsKeyUp);
            }
            if (!WindowsInputInterop.SendAll(inputs))
            {
                return false;
            }
        }
        return true;
    }

    public bool Press(IReadOnlyList<string> keys)
    {
        ArgumentNullException.ThrowIfNull(keys);
        var inputs = new WindowsInputInterop.NativeInput[keys.Count * 2];
        for (var index = 0; index < keys.Count; index++)
        {
            if (!VirtualKeys.TryGetValue(keys[index], out var virtualKey))
            {
                return false;
            }
            inputs[index * 2] = WindowsInputInterop.CreateVirtualKey(virtualKey, keyUp: false);
            inputs[(index * 2) + 1] = WindowsInputInterop.CreateVirtualKey(virtualKey, keyUp: true);
        }
        return WindowsInputInterop.SendAll(inputs);
    }
}
