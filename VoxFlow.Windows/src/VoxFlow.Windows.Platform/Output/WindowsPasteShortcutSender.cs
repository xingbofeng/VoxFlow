namespace VoxFlow.Windows.Platform.Output;

public sealed class WindowsPasteShortcutSender : IPasteShortcutSender
{
    private const ushort VirtualKeyControl = 0x11;
    private const ushort VirtualKeyV = 0x56;

    public bool SendCtrlV()
    {
        WindowsInputInterop.NativeInput[] inputs =
        [
            WindowsInputInterop.CreateVirtualKey(VirtualKeyControl, keyUp: false),
            WindowsInputInterop.CreateVirtualKey(VirtualKeyV, keyUp: false),
            WindowsInputInterop.CreateVirtualKey(VirtualKeyV, keyUp: true),
            WindowsInputInterop.CreateVirtualKey(VirtualKeyControl, keyUp: true),
        ];

        return WindowsInputInterop.SendAll(inputs);
    }
}
