using System.IO;
using System.Text;

namespace VoxFlow.Windows.App.Theming;

public sealed class FileThemePreferenceStore(string preferencePath) : IThemePreferenceStore
{
    private readonly string preferencePath = string.IsNullOrWhiteSpace(preferencePath)
        ? throw new ArgumentException("A theme preference path is required.", nameof(preferencePath))
        : Path.GetFullPath(preferencePath);

    public AppThemeMode Load()
    {
        try
        {
            if (!File.Exists(preferencePath))
            {
                return AppThemeMode.Light;
            }

            var persisted = File.ReadAllText(preferencePath, Encoding.UTF8).Trim();
            return Enum.TryParse<AppThemeMode>(persisted, ignoreCase: true, out var mode)
                ? mode
                : AppThemeMode.Light;
        }
        catch (IOException)
        {
            return AppThemeMode.Light;
        }
        catch (UnauthorizedAccessException)
        {
            return AppThemeMode.Light;
        }
    }

    public void Save(AppThemeMode mode)
    {
        var directory = Path.GetDirectoryName(preferencePath)
            ?? throw new InvalidOperationException("The theme preference path has no parent directory.");
        Directory.CreateDirectory(directory);

        var temporaryPath = preferencePath + ".tmp";
        File.WriteAllText(temporaryPath, mode.ToString(), new UTF8Encoding(false));
        File.Move(temporaryPath, preferencePath, overwrite: true);
    }
}
