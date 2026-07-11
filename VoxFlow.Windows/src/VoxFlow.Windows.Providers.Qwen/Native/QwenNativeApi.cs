using Microsoft.Win32.SafeHandles;
using System.Text;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Qwen.Native;

internal interface IQwenNativeApi
{
    int AbiVersion { get; }

    QwenRuntimeSafeHandle CreateRuntime(string modelPath);

    QwenSessionSafeHandle CreateSession(QwenRuntimeSafeHandle runtime, int variant);

    int Start(QwenSessionSafeHandle session);

    int PushPcm16(QwenSessionSafeHandle session, ReadOnlySpan<short> samples);

    QwenNativePollResult Poll(
        QwenSessionSafeHandle session,
        out QwenNativeEventData @event);

    int Finish(QwenSessionSafeHandle session);

    void Cancel(QwenSessionSafeHandle session);

    string GetLastError(QwenSessionSafeHandle session);

    void DestroyRuntime(nint runtime);

    void DestroySession(nint session);
}

internal sealed class QwenNativeApi : IQwenNativeApi
{
    private const int MaximumErrorBytes = 4096;

    public int AbiVersion => QwenNativeMethods.AbiVersion();

    public QwenRuntimeSafeHandle CreateRuntime(string modelPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelPath);

        int status = QwenNativeMethods.RuntimeCreate(modelPath, out nint runtime);
        if (status != 0 || runtime == 0)
        {
            throw new QwenNativeCallException("runtime_create", status);
        }

        return new QwenRuntimeSafeHandle(runtime, this);
    }

    public QwenSessionSafeHandle CreateSession(
        QwenRuntimeSafeHandle runtime,
        int variant)
    {
        ArgumentNullException.ThrowIfNull(runtime);

        int status = QwenNativeMethods.SessionCreate(runtime, variant, out nint session);
        if (status != 0 || session == 0)
        {
            throw new QwenNativeCallException("session_create", status);
        }

        return new QwenSessionSafeHandle(session, this);
    }

    public int Start(QwenSessionSafeHandle session) =>
        QwenNativeMethods.SessionStart(session);

    public int PushPcm16(
        QwenSessionSafeHandle session,
        ReadOnlySpan<short> samples)
    {
        if (samples.IsEmpty)
        {
            return 0;
        }

        short[] copy = samples.ToArray();
        return QwenNativeMethods.SessionPushPcm16(
            session,
            copy,
            (nuint)copy.Length);
    }

    public QwenNativePollResult Poll(
        QwenSessionSafeHandle session,
        out QwenNativeEventData @event)
    {
        QwenNativePollResult result = (QwenNativePollResult)QwenNativeMethods.SessionPoll(
            session,
            out QwenNativeEventRaw raw);
        @event = result == QwenNativePollResult.Event
            ? QwenNativeEventMarshaller.Copy(raw)
            : new QwenNativeEventData(QwenNativeEventKind.Progress, 0, string.Empty, 0);
        return result;
    }

    public int Finish(QwenSessionSafeHandle session) =>
        QwenNativeMethods.SessionFinish(session);

    public void Cancel(QwenSessionSafeHandle session) =>
        QwenNativeMethods.SessionCancel(session);

    public string GetLastError(QwenSessionSafeHandle session)
    {
        byte[] buffer = new byte[MaximumErrorBytes];
        int status = QwenNativeMethods.SessionLastError(
            session,
            buffer,
            (nuint)buffer.Length,
            out nuint requiredBytes);
        if (status != 0 || requiredBytes == 0)
        {
            return "The native Qwen runtime failed.";
        }

        int length = checked((int)Math.Min(requiredBytes, (nuint)buffer.Length));
        if (length > 0 && buffer[length - 1] == 0)
        {
            length--;
        }

        try
        {
            return new UTF8Encoding(false, true).GetString(buffer, 0, length);
        }
        catch (DecoderFallbackException)
        {
            return "The native Qwen runtime returned an unreadable error.";
        }
    }

    public void DestroyRuntime(nint runtime) =>
        QwenNativeMethods.RuntimeDestroy(runtime);

    public void DestroySession(nint session) =>
        QwenNativeMethods.SessionDestroy(session);
}

internal sealed class QwenRuntimeSafeHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    private readonly IQwenNativeApi api;

    internal QwenRuntimeSafeHandle(nint handle, IQwenNativeApi api)
        : base(ownsHandle: true)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
        SetHandle(handle);
    }

    protected override bool ReleaseHandle()
    {
        api.DestroyRuntime(handle);
        return true;
    }
}

internal sealed class QwenSessionSafeHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    private readonly IQwenNativeApi api;

    internal QwenSessionSafeHandle(nint handle, IQwenNativeApi api)
        : base(ownsHandle: true)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
        SetHandle(handle);
    }

    protected override bool ReleaseHandle()
    {
        api.DestroySession(handle);
        return true;
    }
}

internal sealed class QwenNativeCallException
    : Exception, IFileTranscriptionProviderErrorException
{
    internal QwenNativeCallException(string operation, int status)
        : base($"The native Qwen operation '{operation}' failed with status {status}.")
    {
        Operation = operation;
        Status = status;
    }

    internal string Operation { get; }

    internal int Status { get; }

    public VoxFlowError Error { get; } = new(
        VoxFlowErrorCode.NativeRuntimeFailure,
        AsrProviderId.Qwen);
}
