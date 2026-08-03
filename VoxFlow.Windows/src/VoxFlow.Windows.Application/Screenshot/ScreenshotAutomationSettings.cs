namespace VoxFlow.Windows.Application.Screenshot;

public sealed record ScreenshotAutomationSettings(
    int SchemaVersion,
    bool ClipboardImageOcrEnabled)
{
    public const int CurrentSchemaVersion = 1;

    public static ScreenshotAutomationSettings Default { get; } = new(
        CurrentSchemaVersion,
        ClipboardImageOcrEnabled: true);

    public bool IsValid => SchemaVersion == CurrentSchemaVersion;
}

public interface IScreenshotAutomationSettingsStore
{
    ValueTask<ScreenshotAutomationSettings> LoadAsync(
        CancellationToken cancellationToken);

    ValueTask SaveAsync(
        ScreenshotAutomationSettings settings,
        CancellationToken cancellationToken);
}
