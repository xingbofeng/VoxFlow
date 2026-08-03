using System.Runtime.InteropServices;
using System.Reflection;

namespace VoxFlow.Windows.Providers.Qwen.Native;

internal static partial class QwenNativeMethods
{
    internal const int ExpectedAbiVersion = 1;
    private const string LibraryName = "qwen_asr";

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_abi_version")]
    internal static partial int AbiVersion();

    [LibraryImport(
        LibraryName,
        EntryPoint = "vf_qwen_runtime_create",
        StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int RuntimeCreate(string modelPath, out nint runtime);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_runtime_destroy")]
    internal static partial void RuntimeDestroy(nint runtime);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_create")]
    internal static partial int SessionCreate(
        QwenRuntimeSafeHandle runtime,
        int variant,
        out nint session);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_start")]
    internal static partial int SessionStart(QwenSessionSafeHandle session);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_push_pcm16")]
    internal static partial int SessionPushPcm16(
        QwenSessionSafeHandle session,
        [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 2)] short[] samples,
        nuint sampleCount);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_poll")]
    internal static partial int SessionPoll(
        QwenSessionSafeHandle session,
        out QwenNativeEventRaw @event);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_finish")]
    internal static partial int SessionFinish(QwenSessionSafeHandle session);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_cancel")]
    internal static partial void SessionCancel(QwenSessionSafeHandle session);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_last_error")]
    internal static partial int SessionLastError(
        QwenSessionSafeHandle session,
        [Out] byte[] destination,
        nuint destinationCapacity,
        out nuint requiredBytes);

    [LibraryImport(LibraryName, EntryPoint = "vf_qwen_session_destroy")]
    internal static partial void SessionDestroy(nint session);
}

internal static class QwenNativeLibrary
{
    private static readonly object ConfigurationLock = new();
    private static string? configuredPath;

    internal static void ConfigureResolver(string absoluteLibraryPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absoluteLibraryPath);
        string fullPath = Path.GetFullPath(absoluteLibraryPath);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException(
                "The configured Qwen native library does not exist.",
                fullPath);
        }

        lock (ConfigurationLock)
        {
            if (configuredPath is not null)
            {
                if (!StringComparer.OrdinalIgnoreCase.Equals(configuredPath, fullPath))
                {
                    throw new InvalidOperationException(
                        "The Qwen native resolver was already configured for a different library.");
                }

                return;
            }

            NativeLibrary.SetDllImportResolver(
                typeof(QwenNativeMethods).Assembly,
                (libraryName, _, _) => StringComparer.Ordinal.Equals(libraryName, "qwen_asr")
                    ? NativeLibrary.Load(fullPath)
                    : 0);
            configuredPath = fullPath;
        }
    }
}
