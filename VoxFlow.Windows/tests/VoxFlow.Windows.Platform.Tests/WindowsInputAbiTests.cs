using System.Runtime.InteropServices;
using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WindowsInputAbiTests
{
    [Fact]
    public void X64_senders_marshal_the_complete_native_input_union()
    {
        if (IntPtr.Size != sizeof(long))
        {
            return;
        }

        Assert.Equal(32, Marshal.SizeOf<WindowsInputInterop.NativeInputUnion>());
        Assert.Equal(40, WindowsInputInterop.NativeInputSize);
    }
}
