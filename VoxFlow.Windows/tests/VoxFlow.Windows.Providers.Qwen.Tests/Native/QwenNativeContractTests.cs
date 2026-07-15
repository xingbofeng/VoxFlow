using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using VoxFlow.Windows.Providers.Qwen.Native;

namespace VoxFlow.Windows.Providers.Qwen.Tests.Native;

public sealed class QwenNativeContractTests
{
    [Fact]
    public void Native_methods_use_library_import_for_the_versioned_C_ABI()
    {
        string[] expectedEntries =
        [
            "vf_qwen_abi_version",
            "vf_qwen_runtime_create",
            "vf_qwen_runtime_destroy",
            "vf_qwen_session_create",
            "vf_qwen_session_start",
            "vf_qwen_session_push_pcm16",
            "vf_qwen_session_poll",
            "vf_qwen_session_finish",
            "vf_qwen_session_cancel",
            "vf_qwen_session_last_error",
            "vf_qwen_session_destroy",
        ];

        var imports = typeof(QwenNativeMethods)
            .GetMethods(BindingFlags.Static | BindingFlags.NonPublic)
            .Select(method => method.GetCustomAttribute<LibraryImportAttribute>())
            .Where(attribute => attribute is not null)
            .Select(attribute => attribute!.EntryPoint)
            .ToArray();

        Assert.Equal(expectedEntries.Order(), imports.Order());
    }

    [Fact]
    public void Safe_handles_release_native_resources_exactly_once()
    {
        var api = new FakeNativeApi();
        var runtime = new QwenRuntimeSafeHandle((nint)41, api);
        var session = new QwenSessionSafeHandle((nint)42, api);

        runtime.Dispose();
        runtime.Dispose();
        session.Dispose();
        session.Dispose();

        Assert.Equal([(nint)41], api.DestroyedRuntimes);
        Assert.Equal([(nint)42], api.DestroyedSessions);
    }

    [Fact]
    public void Native_event_text_is_copied_as_bounded_UTF8_before_poll_returns()
    {
        const string expected = "语音输入 ✅";
        byte[] utf8 = Encoding.UTF8.GetBytes(expected);
        nint memory = Marshal.AllocHGlobal(utf8.Length);

        try
        {
            Marshal.Copy(utf8, 0, memory, utf8.Length);
            var raw = new QwenNativeEventRaw(
                QwenNativeEventKind.Partial,
                revision: 7,
                text: memory,
                textLength: (nuint)utf8.Length,
                value: 0);

            QwenNativeEventData copied = QwenNativeEventMarshaller.Copy(raw);
            Marshal.WriteByte(memory, 0, (byte)'X');

            Assert.Equal(expected, copied.Text);
            Assert.Equal(7, copied.Revision);
        }
        finally
        {
            Marshal.FreeHGlobal(memory);
        }
    }

    [Fact]
    public void Native_event_text_rejects_an_unbounded_payload()
    {
        var raw = new QwenNativeEventRaw(
            QwenNativeEventKind.Final,
            revision: 0,
            text: (nint)1,
            textLength: (nuint)(QwenNativeEventMarshaller.MaximumTextBytes + 1),
            value: 0);

        Assert.Throws<InvalidDataException>(() => QwenNativeEventMarshaller.Copy(raw));
    }

    private sealed class FakeNativeApi : IQwenNativeApi
    {
        public List<nint> DestroyedRuntimes { get; } = [];

        public List<nint> DestroyedSessions { get; } = [];

        public int AbiVersion => QwenNativeMethods.ExpectedAbiVersion;

        public QwenRuntimeSafeHandle CreateRuntime(string modelPath) => throw new NotSupportedException();

        public QwenSessionSafeHandle CreateSession(QwenRuntimeSafeHandle runtime, int variant) => throw new NotSupportedException();

        public int Start(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public int PushPcm16(QwenSessionSafeHandle session, ReadOnlySpan<short> samples) => throw new NotSupportedException();

        public QwenNativePollResult Poll(QwenSessionSafeHandle session, out QwenNativeEventData @event)
        {
            throw new NotSupportedException();
        }

        public int Finish(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public void Cancel(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public string GetLastError(QwenSessionSafeHandle session) => throw new NotSupportedException();

        public void DestroyRuntime(nint runtime) => DestroyedRuntimes.Add(runtime);

        public void DestroySession(nint session) => DestroyedSessions.Add(session);
    }
}
