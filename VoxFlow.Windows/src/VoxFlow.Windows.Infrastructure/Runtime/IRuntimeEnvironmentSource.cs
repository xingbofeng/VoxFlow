using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Infrastructure.Runtime;

public interface IRuntimeEnvironmentSource
{
    bool IsWindows { get; }

    Version OperatingSystemVersion { get; }

    Architecture ProcessArchitecture { get; }

    string LocalApplicationDataPath { get; }

    bool FileExists(string path);
}
