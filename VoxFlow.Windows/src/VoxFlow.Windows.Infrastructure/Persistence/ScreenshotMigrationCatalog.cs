namespace VoxFlow.Windows.Infrastructure.Persistence;

public static class ScreenshotMigrationCatalog
{
    private const string ScreenshotMigrationResource =
        "VoxFlow.Windows.Infrastructure.Persistence.Migrations.V004__screenshot_records.sql";

    public static IReadOnlyList<SqliteMigration> All()
    {
        var assembly = typeof(ScreenshotMigrationCatalog).Assembly;
        using var stream = assembly.GetManifestResourceStream(ScreenshotMigrationResource)
            ?? throw new InvalidOperationException(
                $"Embedded database migration '{ScreenshotMigrationResource}' was not found.");
        using var reader = new StreamReader(stream);
        return [new SqliteMigration(4, "screenshot_records", reader.ReadToEnd())];
    }
}
