using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Platform.Input;

public static class WindowsHotkeyBindingCapture
{
    private const uint MapVkToVsc = 0;

    public static HotkeyBinding Create(
        uint virtualKey,
        HotkeyModifiers modifiers,
        bool isExtended) => new(
        virtualKey,
        MapVirtualKey(virtualKey, MapVkToVsc),
        modifiers,
        isExtended);

    [DllImport("user32.dll", EntryPoint = "MapVirtualKeyW")]
    private static extern uint MapVirtualKey(uint code, uint mapType);
}
