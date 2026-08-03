using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Infrastructure.Runtime;

public sealed class SystemRuntimeEnvironmentSource : IRuntimeEnvironmentSource
{
    public bool IsWindows => OperatingSystem.IsWindows();

    public Version OperatingSystemVersion => Environment.OSVersion.Version;

    public Architecture ProcessArchitecture => RuntimeInformation.ProcessArchitecture;

    public string LocalApplicationDataPath => Environment.GetFolderPath(
        Environment.SpecialFolder.LocalApplicationData);

    public bool FileExists(string path) => File.Exists(path);
}
