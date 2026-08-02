using System.Text.Json;
using System.IO;

namespace VoxFlow.Windows.App.Settings;

public sealed record GeneralPreferenceDocument(
    int SchemaVersion,
    string UiLanguageId,
    bool GrayTrayIcon,
    bool CapsLockIndicator,
    bool StreamPreview,
    bool AutoReleaseModels)
{
    public const int CurrentSchemaVersion = 1;

    public static GeneralPreferenceDocument Default { get; } = new(
        CurrentSchemaVersion,
        "system",
        GrayTrayIcon: false,
        CapsLockIndicator: false,
        StreamPreview: true,
        AutoReleaseModels: false);

    public GeneralPreferenceDocument Normalize()
    {
        var language = UiLanguageId?.Trim() switch
        {
            "zh-Hans" => "zh-Hans",
            "zh-Hant" => "zh-Hant",
            "en" => "en",
            "ja" => "ja",
            "ko" => "ko",
            _ => "system",
        };
        return this with
        {
            SchemaVersion = CurrentSchemaVersion,
            UiLanguageId = language,
        };
    }
}

public sealed class GeneralPreferenceStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string path;
    private readonly object gate = new();

    public GeneralPreferenceStore(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        this.path = Path.GetFullPath(path);
    }

    public GeneralPreferenceDocument Load()
    {
        lock (gate)
        {
            try
            {
                if (!File.Exists(path))
                {
                    return GeneralPreferenceDocument.Default;
                }
                var value = JsonSerializer.Deserialize<GeneralPreferenceDocument>(
                    File.ReadAllText(path),
                    JsonOptions);
                return value?.Normalize() ?? GeneralPreferenceDocument.Default;
            }
            catch (Exception exception) when (exception is
                IOException or UnauthorizedAccessException or JsonException)
            {
                return GeneralPreferenceDocument.Default;
            }
        }
    }

    public void Save(GeneralPreferenceDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        lock (gate)
        {
            var normalized = document.Normalize();
            var directory = Path.GetDirectoryName(path)
                ?? throw new InvalidOperationException("Preference path has no parent directory.");
            Directory.CreateDirectory(directory);
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(normalized, JsonOptions));
            File.Move(temporary, path, overwrite: true);
        }
    }
}
