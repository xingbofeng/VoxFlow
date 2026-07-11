namespace VoxFlow.Windows.Infrastructure.Runtime;

public sealed class RuntimeEnvironmentProbe(IRuntimeEnvironmentSource source)
{
    public static Version MinimumWindowsVersion { get; } = new(10, 0, 17763, 0);

    public RuntimeEnvironmentReport Inspect(string installationRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(installationRoot);

        if (string.IsNullOrWhiteSpace(source.LocalApplicationDataPath))
        {
            throw new InvalidOperationException("The local application-data path is unavailable.");
        }

        var applicationDataRoot = Path.Combine(source.LocalApplicationDataPath, "VoxFlow");
        var missingDependencies = InstallerLayoutContract.RequiredRelativePaths
            .Where(relativePath => !source.FileExists(Path.Combine(installationRoot, relativePath)))
            .ToArray();

        return new RuntimeEnvironmentReport(
            source.IsWindows,
            source.OperatingSystemVersion,
            source.ProcessArchitecture,
            applicationDataRoot,
            missingDependencies);
    }
}
