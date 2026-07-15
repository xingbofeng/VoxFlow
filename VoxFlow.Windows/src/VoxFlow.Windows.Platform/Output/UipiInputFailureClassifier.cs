using System.Runtime.InteropServices;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Output;

public enum InputIntegrityRelation
{
    EqualOrLower,
    Higher,
    Unknown,
}

public interface IInputIntegrityProbe
{
    InputIntegrityRelation CompareWithCurrentProcess(int targetProcessId);
}

public static class InputFailureClassifier
{
    public static OutputResult Classify(InputIntegrityRelation relation) =>
        relation == InputIntegrityRelation.Higher
            ? new OutputResult(
                OutputResultKind.PermissionDenied,
                VoxFlowErrorCode.InputPermissionDenied)
            : new OutputResult(
                OutputResultKind.InjectionFailed,
                VoxFlowErrorCode.InputInjectionFailure);
}

public sealed class UipiAwareTextOutputInjector : ITextOutputInjector
{
    private readonly ITextOutputInjector inner;
    private readonly IForegroundTargetProvider foregroundTargets;
    private readonly IInputIntegrityProbe integrityProbe;

    public UipiAwareTextOutputInjector(
        ITextOutputInjector inner,
        IForegroundTargetProvider foregroundTargets,
        IInputIntegrityProbe integrityProbe)
    {
        this.inner = inner ?? throw new ArgumentNullException(nameof(inner));
        this.foregroundTargets = foregroundTargets
            ?? throw new ArgumentNullException(nameof(foregroundTargets));
        this.integrityProbe = integrityProbe
            ?? throw new ArgumentNullException(nameof(integrityProbe));
    }

    public async ValueTask<OutputResult> InjectAsync(
        string text,
        CancellationToken cancellationToken)
    {
        var result = await inner.InjectAsync(text, cancellationToken)
            .ConfigureAwait(false);
        if (result.Kind != OutputResultKind.InjectionFailed)
        {
            return result;
        }

        var target = foregroundTargets.CaptureCurrent();
        var relation = target is null
            ? InputIntegrityRelation.Unknown
            : integrityProbe.CompareWithCurrentProcess(target.ProcessId);
        return InputFailureClassifier.Classify(relation);
    }
}

public sealed class WindowsInputIntegrityProbe : IInputIntegrityProbe
{
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint TokenQuery = 0x0008;
    private const int TokenIntegrityLevel = 25;

    public InputIntegrityRelation CompareWithCurrentProcess(int targetProcessId)
    {
        if (!OperatingSystem.IsWindows() || targetProcessId <= 0)
        {
            return InputIntegrityRelation.Unknown;
        }

        nint targetProcess = nint.Zero;
        try
        {
            if (!TryReadIntegrityRid(NativeMethods.GetCurrentProcess(), out var currentRid))
            {
                return InputIntegrityRelation.Unknown;
            }

            targetProcess = NativeMethods.OpenProcess(
                ProcessQueryLimitedInformation,
                inheritHandle: false,
                targetProcessId);
            if (targetProcess == nint.Zero
                || !TryReadIntegrityRid(targetProcess, out var targetRid))
            {
                return InputIntegrityRelation.Unknown;
            }

            return targetRid > currentRid
                ? InputIntegrityRelation.Higher
                : InputIntegrityRelation.EqualOrLower;
        }
        catch (Exception exception) when (
            exception is ExternalException or ArgumentException)
        {
            return InputIntegrityRelation.Unknown;
        }
        finally
        {
            if (targetProcess != nint.Zero)
            {
                _ = NativeMethods.CloseHandle(targetProcess);
            }
        }
    }

    private static bool TryReadIntegrityRid(nint process, out int integrityRid)
    {
        integrityRid = 0;
        if (!NativeMethods.OpenProcessToken(process, TokenQuery, out var token)
            || token == nint.Zero)
        {
            return false;
        }

        try
        {
            _ = NativeMethods.GetTokenInformation(
                token,
                TokenIntegrityLevel,
                nint.Zero,
                0,
                out var requiredLength);
            if (requiredLength <= 0)
            {
                return false;
            }

            var buffer = Marshal.AllocHGlobal(requiredLength);
            try
            {
                if (!NativeMethods.GetTokenInformation(
                        token,
                        TokenIntegrityLevel,
                        buffer,
                        requiredLength,
                        out _))
                {
                    return false;
                }

                var label = Marshal.PtrToStructure<TokenMandatoryLabel>(buffer);
                if (label.Label.Sid == nint.Zero)
                {
                    return false;
                }

                var countPointer = NativeMethods.GetSidSubAuthorityCount(label.Label.Sid);
                if (countPointer == nint.Zero)
                {
                    return false;
                }

                var count = Marshal.ReadByte(countPointer);
                if (count == 0)
                {
                    return false;
                }

                var ridPointer = NativeMethods.GetSidSubAuthority(
                    label.Label.Sid,
                    (uint)(count - 1));
                if (ridPointer == nint.Zero)
                {
                    return false;
                }

                integrityRid = Marshal.ReadInt32(ridPointer);
                return true;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            _ = NativeMethods.CloseHandle(token);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct SidAndAttributes
    {
        public readonly nint Sid;
        public readonly uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct TokenMandatoryLabel
    {
        public readonly SidAndAttributes Label;
    }

    private static class NativeMethods
    {
        [DllImport("kernel32.dll")]
        public static extern nint GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern nint OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            int processId);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool OpenProcessToken(
            nint processHandle,
            uint desiredAccess,
            out nint tokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetTokenInformation(
            nint tokenHandle,
            int tokenInformationClass,
            nint tokenInformation,
            int tokenInformationLength,
            out int returnLength);

        [DllImport("advapi32.dll")]
        public static extern nint GetSidSubAuthorityCount(nint sid);

        [DllImport("advapi32.dll")]
        public static extern nint GetSidSubAuthority(nint sid, uint subAuthorityIndex);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(nint handle);
    }
}
