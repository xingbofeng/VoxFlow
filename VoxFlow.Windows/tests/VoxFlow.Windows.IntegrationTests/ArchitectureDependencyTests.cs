using System.Xml.Linq;

namespace VoxFlow.Windows.IntegrationTests;

public sealed class ArchitectureDependencyTests
{
    private static readonly IReadOnlyDictionary<string, string[]> ExpectedReferences =
        new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            ["VoxFlow.Windows.Domain"] = [],
            ["VoxFlow.Windows.Application"] = ["VoxFlow.Windows.Domain"],
            ["VoxFlow.Windows.Infrastructure"] =
                ["VoxFlow.Windows.Application", "VoxFlow.Windows.Domain"],
            ["VoxFlow.Windows.Platform"] =
                ["VoxFlow.Windows.Application", "VoxFlow.Windows.Domain"],
            ["VoxFlow.Windows.Providers.Qwen"] =
                ["VoxFlow.Windows.Application", "VoxFlow.Windows.Domain"],
            ["VoxFlow.Windows.Providers.Cloud"] =
                ["VoxFlow.Windows.Application", "VoxFlow.Windows.Domain"],
            ["VoxFlow.Windows.App"] =
                [
                    "VoxFlow.Windows.Application",
                    "VoxFlow.Windows.Domain",
                    "VoxFlow.Windows.Infrastructure",
                    "VoxFlow.Windows.Platform",
                    "VoxFlow.Windows.Providers.Cloud",
                    "VoxFlow.Windows.Providers.Qwen",
                ],
        };

    [Fact]
    public void Production_projects_follow_the_approved_dependency_direction()
    {
        var solutionRoot = FindSolutionRoot();
        var discoveredProjects = DiscoverProductionProjects(solutionRoot);

        ApprovedProductionProjectSet.EnsureExactMatch(
            ExpectedReferences.Keys,
            discoveredProjects.Keys);

        foreach (var (projectName, expectedReferences) in ExpectedReferences)
        {
            var projectFile = discoveredProjects[projectName];
            var actualReferences = ReadProjectReferences(projectFile);

            Assert.Equal(
                expectedReferences.Order(StringComparer.Ordinal),
                actualReferences.Order(StringComparer.Ordinal));
        }
    }

    [Fact]
    public void Unknown_production_projects_are_rejected()
    {
        var exception = Assert.Throws<InvalidOperationException>(() =>
            ApprovedProductionProjectSet.EnsureExactMatch(
                ["VoxFlow.Windows.Domain"],
                ["VoxFlow.Windows.Domain", "VoxFlow.Windows.Rogue"]));

        Assert.Contains("VoxFlow.Windows.Rogue", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void File_transcription_keeps_platform_and_provider_details_out_of_core_layers()
    {
        var solutionRoot = FindSolutionRoot();
        AssertSourceTreeExcludes(
            Path.Combine(solutionRoot, "src", "VoxFlow.Windows.Domain"),
            "System.Windows",
            "Microsoft.Data.Sqlite",
            "FFmpeg",
            "NAudio",
            "VoxFlow.Windows.Providers");
        AssertSourceTreeExcludes(
            Path.Combine(solutionRoot, "src", "VoxFlow.Windows.Application"),
            "System.Windows",
            "Microsoft.Data.Sqlite",
            "System.Diagnostics.Process",
            "NAudio",
            "VoxFlow.Windows.Providers");
    }

    private static void AssertSourceTreeExcludes(string directory, params string[] forbiddenTokens)
    {
        foreach (var sourceFile in Directory.EnumerateFiles(directory, "*.cs", SearchOption.AllDirectories))
        {
            var source = File.ReadAllText(sourceFile);
            foreach (var token in forbiddenTokens)
            {
                Assert.DoesNotContain(token, source, StringComparison.Ordinal);
            }
        }
    }

    private static IReadOnlyDictionary<string, string> DiscoverProductionProjects(
        string solutionRoot) =>
        Directory
            .EnumerateFiles(
                Path.Combine(solutionRoot, "src"),
                "*.csproj",
                SearchOption.AllDirectories)
            .ToDictionary(
                path => Path.GetFileNameWithoutExtension(path)!,
                path => path,
                StringComparer.Ordinal);

    private static class ApprovedProductionProjectSet
    {
        public static void EnsureExactMatch(
            IEnumerable<string> approvedProjects,
            IEnumerable<string> discoveredProjects)
        {
            var approved = approvedProjects.ToHashSet(StringComparer.Ordinal);
            var discovered = discoveredProjects.ToHashSet(StringComparer.Ordinal);
            var missing = approved.Except(discovered).Order(StringComparer.Ordinal).ToArray();
            var unexpected = discovered.Except(approved).Order(StringComparer.Ordinal).ToArray();

            if (missing.Length == 0 && unexpected.Length == 0)
            {
                return;
            }

            throw new InvalidOperationException(
                $"Production project set differs from the approved architecture. " +
                $"Missing: [{string.Join(", ", missing)}]. " +
                $"Unexpected: [{string.Join(", ", unexpected)}].");
        }
    }

    private static IReadOnlyCollection<string> ReadProjectReferences(string projectFile)
    {
        var document = XDocument.Load(projectFile);

        return document
            .Descendants("ProjectReference")
            .Select(element => element.Attribute("Include")?.Value)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Select(path => Path.GetFileNameWithoutExtension(path!))
            .ToArray();
    }

    private static string FindSolutionRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "VoxFlow.Windows.sln")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate VoxFlow.Windows.sln.");
    }
}
