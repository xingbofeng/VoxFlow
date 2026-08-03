using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Infrastructure.Runtime;

public sealed record RuntimeEnvironmentReport(
    bool IsWindows,
    Version OperatingSystemVersion,
    Architecture ProcessArchitecture,
    string ApplicationDataRoot,
    IReadOnlyList<string> MissingInstallerDependencies)
{
    public bool IsSupported =>
        IsWindows
        && OperatingSystemVersion.CompareTo(RuntimeEnvironmentProbe.MinimumWindowsVersion) >= 0
        && ProcessArchitecture == Architecture.X64;
}
