using VoxFlow.Windows.Application.Features;

namespace VoxFlow.Windows.Infrastructure.Persistence;

/// <summary>
/// Migration extension point for the default-off interactive features. Until
/// V003 is registered, enabled flags fail closed instead of starting against a
/// partial schema. Disabled flags preserve the exact V001/V002 baseline.
/// </summary>
public static class InteractiveFeatureMigrationCatalog
{
    private const string InteractiveWorkflowMigrationResource =
        "VoxFlow.Windows.Infrastructure.Persistence.Migrations.V003__interactive_workflows.sql";

    public static IReadOnlyList<SqliteMigration> For(
        WindowsInteractiveFeatureFlags flags)
    {
        ArgumentNullException.ThrowIfNull(flags);
        if (!flags.AnyEnabled)
        {
            return Array.Empty<SqliteMigration>();
        }

        return [LoadInteractiveWorkflowMigration()];
    }

    private static SqliteMigration LoadInteractiveWorkflowMigration()
    {
        var assembly = typeof(InteractiveFeatureMigrationCatalog).Assembly;
        using var stream = assembly.GetManifestResourceStream(
            InteractiveWorkflowMigrationResource)
            ?? throw new InvalidOperationException(
                $"Embedded database migration '{InteractiveWorkflowMigrationResource}' was not found.");
        using var reader = new StreamReader(stream);
        return new SqliteMigration(
            3,
            "interactive_workflows",
            reader.ReadToEnd());
    }
}
