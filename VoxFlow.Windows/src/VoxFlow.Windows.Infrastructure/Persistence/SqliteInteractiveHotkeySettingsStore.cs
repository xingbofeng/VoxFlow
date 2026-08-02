using System.Text.Json;
using VoxFlow.Windows.Application.Features;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteInteractiveHotkeySettingsStore
    : IInteractiveHotkeySettingsStore
{
    private const string SettingsKey = "interactive.hotkeys";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteInteractiveHotkeySettingsStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<InteractiveHotkeySettingsDocument> LoadAsync(
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            return command.ExecuteScalar() as string;
        });
        if (json is null)
        {
            return ValueTask.FromResult(InteractiveHotkeySettingsDocument.Default);
        }

        try
        {
            var settings = JsonSerializer.Deserialize<InteractiveHotkeySettingsDocument>(
                json,
                JsonOptions);
            var migrated = false;
            if (settings?.SchemaVersion
                == InteractiveHotkeySettingsDocument.SchemaVersionWithoutScreenshot)
            {
                settings = settings with
                {
                    SchemaVersion = InteractiveHotkeySettingsDocument
                        .SchemaVersionWithConflictProneDefaults,
                    Screenshot = InteractiveHotkeySettingsDocument
                        .ConflictProneDefaults.Screenshot,
                };
                migrated = true;
            }
            if (settings?.SchemaVersion
                == InteractiveHotkeySettingsDocument.SchemaVersionWithConflictProneDefaults)
            {
                var legacy = InteractiveHotkeySettingsDocument.ConflictProneDefaults;
                settings = settings with
                {
                    SchemaVersion = InteractiveHotkeySettingsDocument.SchemaVersionWithoutSelectionAskAi,
                    Screenshot = settings.Screenshot == legacy.Screenshot
                        ? InteractiveHotkeySettingsDocument.CtrlShiftScreenshotDefault
                        : settings.Screenshot,
                    SelectionTranslation = ClearLegacyDefault(
                        settings.SelectionTranslation,
                        legacy.SelectionTranslation),
                    SelectionSummary = ClearLegacyDefault(
                        settings.SelectionSummary,
                        legacy.SelectionSummary),
                    AgentCompose = ClearLegacyDefault(
                        settings.AgentCompose,
                        legacy.AgentCompose),
                };
                migrated = true;
            }
            if (settings?.SchemaVersion
                == InteractiveHotkeySettingsDocument.SchemaVersionWithoutSelectionAskAi)
            {
                settings = settings with
                {
                    SchemaVersion = InteractiveHotkeySettingsDocument.SchemaVersionWithoutClipboardImageOcr,
                    SelectionAskAi = null,
                };
                migrated = true;
            }
            if (settings?.SchemaVersion
                == InteractiveHotkeySettingsDocument.SchemaVersionWithoutClipboardImageOcr)
            {
                settings = settings with
                {
                    SchemaVersion = InteractiveHotkeySettingsDocument
                        .SchemaVersionWithCtrlShiftDefaults,
                    ClipboardImageOcr = InteractiveHotkeySettingsDocument
                        .CtrlShiftClipboardImageOcrDefault,
                };
                migrated = true;
            }
            if (settings?.SchemaVersion
                == InteractiveHotkeySettingsDocument.SchemaVersionWithCtrlShiftDefaults)
            {
                // mac ⌘+Shift → Alt+Shift. Migrate factory Ctrl+Shift screenshot /
                // clipboard bindings; fill unbound selection workflows with the
                // new Alt+Shift letter defaults when they do not collide. Preserve
                // non-factory custom bindings as-is.
                var screenshot = settings.Screenshot
                    == InteractiveHotkeySettingsDocument.CtrlShiftScreenshotDefault
                        ? InteractiveHotkeySettingsDocument.ScreenshotDefault
                        : settings.Screenshot;
                var clipboard = settings.ClipboardImageOcr
                    == InteractiveHotkeySettingsDocument.CtrlShiftClipboardImageOcrDefault
                        ? InteractiveHotkeySettingsDocument.ClipboardImageOcrDefault
                        : settings.ClipboardImageOcr
                          ?? InteractiveHotkeySettingsDocument.ClipboardImageOcrDefault;
                var taken = new HashSet<HotkeyBindingSetting>(
                    new[] { screenshot, clipboard, settings.SelectionTranslation,
                        settings.SelectionSummary, settings.AgentCompose,
                        settings.SelectionAskAi }
                        .Where(binding => binding is not null)
                        .Select(binding => binding!)!);
                settings = settings with
                {
                    SchemaVersion = InteractiveHotkeySettingsDocument.SchemaVersionWithoutDictation,
                    Screenshot = screenshot,
                    ClipboardImageOcr = clipboard,
                    SelectionTranslation = FillUnboundWithoutCollision(
                        settings.SelectionTranslation,
                        InteractiveHotkeySettingsDocument.SelectionTranslationDefault,
                        taken),
                    SelectionSummary = FillUnboundWithoutCollision(
                        settings.SelectionSummary,
                        InteractiveHotkeySettingsDocument.SelectionSummaryDefault,
                        taken),
                    AgentCompose = FillUnboundWithoutCollision(
                        settings.AgentCompose,
                        InteractiveHotkeySettingsDocument.AgentComposeDefault,
                        taken),
                    SelectionAskAi = FillUnboundWithoutCollision(
                        settings.SelectionAskAi,
                        InteractiveHotkeySettingsDocument.SelectionAskAiDefault,
                        taken),
                };
                migrated = true;
            }
            if (settings?.SchemaVersion
                == InteractiveHotkeySettingsDocument.SchemaVersionWithoutDictation)
            {
                settings = settings with
                {
                    SchemaVersion = InteractiveHotkeySettingsDocument.CurrentSchemaVersion,
                    Dictation = InteractiveHotkeySettingsDocument.DictationDefault,
                };
                migrated = true;
            }
            if (settings is null || !settings.IsValid)
            {
                throw new InvalidDataException(
                    "Stored interactive hotkey settings are invalid.");
            }
            if (migrated)
            {
                Write(settings);
            }
            return ValueTask.FromResult(settings);
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception) when (exception is
            JsonException or
            NotSupportedException or
            ArgumentException)
        {
            throw new InvalidDataException(
                "Stored interactive hotkey settings are invalid.",
                exception);
        }
    }

    public ValueTask SaveAsync(
        InteractiveHotkeySettingsDocument settings,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(settings);
        cancellationToken.ThrowIfCancellationRequested();
        if (!settings.IsValid)
        {
            throw new ArgumentException(
                "Only valid current interactive hotkey settings can be saved.",
                nameof(settings));
        }

        Write(settings);
        return ValueTask.CompletedTask;
    }

    private static HotkeyBindingSetting? ClearLegacyDefault(
        HotkeyBindingSetting? current,
        HotkeyBindingSetting? legacyDefault) => current == legacyDefault
            ? null
            : current;

    private static HotkeyBindingSetting? FillUnboundWithoutCollision(
        HotkeyBindingSetting? current,
        HotkeyBindingSetting factoryDefault,
        HashSet<HotkeyBindingSetting> taken)
    {
        if (current is not null)
        {
            return current;
        }

        if (taken.Contains(factoryDefault))
        {
            return null;
        }

        taken.Add(factoryDefault);
        return factoryDefault;
    }

    private void Write(InteractiveHotkeySettingsDocument settings)
    {
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ($key, $json, $updatedAt) " +
                "ON CONFLICT(key) DO UPDATE SET " +
                "json_value = excluded.json_value, " +
                "updated_at_unix_ms = excluded.updated_at_unix_ms;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            command.Parameters.AddWithValue("$json", json);
            command.Parameters.AddWithValue(
                "$updatedAt",
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            _ = command.ExecuteNonQuery();
            return 0;
        });
    }
}
