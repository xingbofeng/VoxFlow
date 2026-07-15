using VoxFlow.Windows.App.Settings;

namespace VoxFlow.Windows.App.Tests;

public sealed class GeneralPreferenceStoreTests
{
    [Fact]
    public void Missing_file_loads_safe_defaults()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var store = new GeneralPreferenceStore(Path.Combine(root, "ui", "general.json"));

            Assert.Equal(GeneralPreferenceDocument.Default, store.Load());
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Save_round_trips_every_general_preference()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var path = Path.Combine(root, "ui", "general.json");
            var expected = new GeneralPreferenceDocument(
                GeneralPreferenceDocument.CurrentSchemaVersion,
                "zh-Hant",
                GrayTrayIcon: true,
                CapsLockIndicator: true,
                StreamPreview: false,
                AutoReleaseModels: true);

            new GeneralPreferenceStore(path).Save(expected);

            Assert.Equal(expected, new GeneralPreferenceStore(path).Load());
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Unsupported_language_and_schema_are_normalized()
    {
        var normalized = new GeneralPreferenceDocument(
            SchemaVersion: 999,
            UiLanguageId: "unsupported",
            GrayTrayIcon: true,
            CapsLockIndicator: false,
            StreamPreview: true,
            AutoReleaseModels: false).Normalize();

        Assert.Equal(GeneralPreferenceDocument.CurrentSchemaVersion, normalized.SchemaVersion);
        Assert.Equal("system", normalized.UiLanguageId);
    }

    private static string CreateTemporaryDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"voxflow-general-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
