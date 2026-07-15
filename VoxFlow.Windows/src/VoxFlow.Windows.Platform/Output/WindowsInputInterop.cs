using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Platform.Output;

internal static class WindowsInputInterop
{
    private const uint InputKeyboard = 1;
    private const uint KeyEventKeyUp = 0x0002;
    private const uint KeyEventUnicode = 0x0004;

    internal static int NativeInputSize => Marshal.SizeOf<NativeInput>();

    internal static NativeInput CreateVirtualKey(ushort virtualKey, bool keyUp) => new()
    {
        Type = InputKeyboard,
        Data = new NativeInputUnion
        {
            Keyboard = new NativeKeyboardInput
            {
                VirtualKey = virtualKey,
                Flags = keyUp ? KeyEventKeyUp : 0,
            },
        },
    };

    internal static NativeInput CreateUnicode(char codeUnit, bool keyUp) => new()
    {
        Type = InputKeyboard,
        Data = new NativeInputUnion
        {
            Keyboard = new NativeKeyboardInput
            {
                ScanCode = codeUnit,
                Flags = KeyEventUnicode | (keyUp ? KeyEventKeyUp : 0),
            },
        },
    };

    internal static bool SendAll(NativeInput[] inputs)
    {
        ArgumentNullException.ThrowIfNull(inputs);
        return SendInput(
            (uint)inputs.Length,
            inputs,
            NativeInputSize) == inputs.Length;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeInput
    {
        public uint Type;
        public NativeInputUnion Data;
    }

    // INPUT contains a union of MOUSEINPUT, KEYBDINPUT, and HARDWAREINPUT.
    // MOUSEINPUT is the largest member (32 bytes on x64), even when callers
    // only populate KEYBDINPUT. Omitting it makes cbSize 32 instead of the
    // required sizeof(INPUT) == 40 and causes SendInput to reject every call.
    [StructLayout(LayoutKind.Explicit)]
    internal struct NativeInputUnion
    {
        [FieldOffset(0)]
        public NativeMouseInput Mouse;

        [FieldOffset(0)]
        public NativeKeyboardInput Keyboard;

        [FieldOffset(0)]
        public NativeHardwareInput Hardware;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeMouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeKeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeHardwareInput
    {
        public uint Message;
        public ushort ParameterLow;
        public ushort ParameterHigh;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(
        uint inputCount,
        [In] NativeInput[] inputs,
        int inputSize);
}
