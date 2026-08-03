using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Selection;

/// <summary>Small, controlled Ctrl+C sender used only inside
/// <see cref="SelectionClipboardTransaction"/> after the frozen foreground
/// target has been reactivated. It never reads clipboard data itself.</summary>
public sealed class WindowsSelectionCopySender : ISelectionCopySender
{
    private const ushort VirtualKeyControl = 0x11;
    private const ushort VirtualKeyC = 0x43;

    public bool SendCtrlC()
    {
        WindowsInputInterop.NativeInput[] inputs =
        [
            WindowsInputInterop.CreateVirtualKey(VirtualKeyControl, keyUp: false),
            WindowsInputInterop.CreateVirtualKey(VirtualKeyC, keyUp: false),
            WindowsInputInterop.CreateVirtualKey(VirtualKeyC, keyUp: true),
            WindowsInputInterop.CreateVirtualKey(VirtualKeyControl, keyUp: true),
        ];
        return WindowsInputInterop.SendAll(inputs);
    }
}
