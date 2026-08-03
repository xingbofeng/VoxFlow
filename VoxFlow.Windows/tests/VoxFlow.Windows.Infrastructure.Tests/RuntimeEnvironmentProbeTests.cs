using System.Runtime.InteropServices;
using VoxFlow.Windows.Infrastructure.Runtime;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class RuntimeEnvironmentProbeTests
{
    [Fact]
    public void Windows_10_1809_x64_with_complete_layout_is_supported()
    {
        const string installationRoot = @"C:\Program Files\VoxFlow";
        var source = new FakeRuntimeEnvironmentSource
        {
            IsWindows = true,
            OperatingSystemVersion = new Version(10, 0, 17763, 1),
            ProcessArchitecture = Architecture.X64,
            LocalApplicationDataPath = @"C:\Users\Test\AppData\Local",
        };
        source.AddCompleteInstallerLayout(installationRoot);

        var report = new RuntimeEnvironmentProbe(source).Inspect(installationRoot);

        Assert.True(report.IsSupported);
        Assert.Equal(
            @"C:\Users\Test\AppData\Local\VoxFlow",
            report.ApplicationDataRoot);
        Assert.Empty(report.MissingInstallerDependencies);
    }

    [Theory]
    [InlineData(17762, Architecture.X64)]
    [InlineData(17763, Architecture.X86)]
    [InlineData(17763, Architecture.Arm64)]
    public void Unsupported_version_or_architecture_is_rejected(
        int build,
        Architecture architecture)
    {
        var source = new FakeRuntimeEnvironmentSource
        {
            IsWindows = true,
            OperatingSystemVersion = new Version(10, 0, build, 0),
            ProcessArchitecture = architecture,
            LocalApplicationDataPath = @"C:\Users\Test\AppData\Local",
        };

        var report = new RuntimeEnvironmentProbe(source).Inspect(@"C:\VoxFlow");

        Assert.False(report.IsSupported);
    }

    [Fact]
    public void Missing_installer_dependencies_are_reported_without_guessing()
    {
        const string installationRoot = @"C:\VoxFlow";
        var source = new FakeRuntimeEnvironmentSource
        {
            IsWindows = true,
            OperatingSystemVersion = new Version(10, 0, 19045, 0),
            ProcessArchitecture = Architecture.X64,
            LocalApplicationDataPath = @"C:\Users\Test\AppData\Local",
        };
        source.ExistingFiles.Add(Path.Combine(
            installationRoot,
            InstallerLayoutContract.ApplicationExecutable));

        var report = new RuntimeEnvironmentProbe(source).Inspect(installationRoot);

        Assert.Equal(
            InstallerLayoutContract.RequiredRelativePaths
                .Where(path => path != InstallerLayoutContract.ApplicationExecutable)
                .Order(StringComparer.Ordinal),
            report.MissingInstallerDependencies.Order(StringComparer.Ordinal));
    }

    private sealed class FakeRuntimeEnvironmentSource : IRuntimeEnvironmentSource
    {
        public bool IsWindows { get; init; }

        public Version OperatingSystemVersion { get; init; } = new(10, 0);

        public Architecture ProcessArchitecture { get; init; }

        public string LocalApplicationDataPath { get; init; } = string.Empty;

        public HashSet<string> ExistingFiles { get; } =
            new(StringComparer.OrdinalIgnoreCase);

        public bool FileExists(string path) => ExistingFiles.Contains(path);

        public void AddCompleteInstallerLayout(string installationRoot)
        {
            foreach (var relativePath in InstallerLayoutContract.RequiredRelativePaths)
            {
                ExistingFiles.Add(Path.Combine(installationRoot, relativePath));
            }
        }
    }
}
