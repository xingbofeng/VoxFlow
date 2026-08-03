using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class InteractiveHotkeySettingsStoreTests
{
    [Fact]
    public async Task Missing_settings_use_alt_shift_defaults_and_rebind_or_clear_round_trip()
    {
        using var fixture = new Fixture();
        Assert.Equal(
            InteractiveHotkeySettingsDocument.Default,
            await fixture.Store.LoadAsync(CancellationToken.None));
        Assert.Equal(
            InteractiveHotkeySettingsDocument.AltShiftModifiers,
            (await fixture.Store.LoadAsync(CancellationToken.None)).Screenshot!.Modifiers);
        var changed = InteractiveHotkeySettingsDocument.Default with
        {
            Screenshot = new HotkeyBindingSetting(
                0x53,
                0x1F,
                modifiers: InteractiveHotkeySettingsDocument.AltShiftModifiers,
                isExtended: false),
            SelectionTranslation = new HotkeyBindingSetting(
                0x55,
                0x16,
                modifiers: InteractiveHotkeySettingsDocument.AltShiftModifiers,
                isExtended: false),
            SelectionSummary = null,
        };

        await fixture.Store.SaveAsync(changed, CancellationToken.None);

        Assert.Equal(changed, await fixture.Store.LoadAsync(CancellationToken.None));
        Assert.Equal(1, fixture.CountRows());
    }

    [Fact]
    public async Task Legacy_schema_adds_default_screenshot_without_changing_user_bindings()
    {
        using var fixture = new Fixture();
        fixture.ReplaceJson("""
            {"schemaVersion":1,"selectionTranslation":{"virtualKey":85,"scanCode":22,"modifiers":3,"isExtended":false},"selectionSummary":null,"agentCompose":{"virtualKey":66,"scanCode":48,"modifiers":5,"isExtended":false}}
            """);

        var migrated = await fixture.Store.LoadAsync(CancellationToken.None);

        Assert.Equal(InteractiveHotkeySettingsDocument.CurrentSchemaVersion, migrated.SchemaVersion);
        Assert.Equal(InteractiveHotkeySettingsDocument.ScreenshotDefault, migrated.Screenshot);
        Assert.Equal(0x55u, migrated.SelectionTranslation?.VirtualKey);
        // Summary was unbound → filled with Alt+Shift+K factory default.
        Assert.Equal(InteractiveHotkeySettingsDocument.SelectionSummaryDefault, migrated.SelectionSummary);
        Assert.Equal(0x42u, migrated.AgentCompose?.VirtualKey);
        Assert.Equal(InteractiveHotkeySettingsDocument.SelectionAskAiDefault, migrated.SelectionAskAi);
        Assert.Equal(InteractiveHotkeySettingsDocument.ClipboardImageOcrDefault, migrated.ClipboardImageOcr);
    }

    [Fact]
    public async Task Legacy_conflicting_defaults_migrate_to_unbound_while_custom_bindings_survive()
    {
        using var fixture = new Fixture();
        fixture.ReplaceJson("""
            {"schemaVersion":2,"screenshot":{"virtualKey":65,"scanCode":30,"modifiers":3,"isExtended":false},"selectionTranslation":{"virtualKey":74,"scanCode":36,"modifiers":3,"isExtended":false},"selectionSummary":{"virtualKey":77,"scanCode":50,"modifiers":7,"isExtended":false},"agentCompose":{"virtualKey":65,"scanCode":30,"modifiers":5,"isExtended":false}}
            """);

        var migrated = await fixture.Store.LoadAsync(CancellationToken.None);

        Assert.Equal(InteractiveHotkeySettingsDocument.CurrentSchemaVersion, migrated.SchemaVersion);
        Assert.Equal(InteractiveHotkeySettingsDocument.ScreenshotDefault, migrated.Screenshot);
        // Conflict-prone Ctrl+Shift+J translation was cleared, then filled with Alt+Shift+F.
        Assert.Equal(
            InteractiveHotkeySettingsDocument.SelectionTranslationDefault,
            migrated.SelectionTranslation);
        // Custom Ctrl+Win+Shift+M survives; agent factory Alt+Shift+L fills unbound.
        Assert.Equal(0x4Du, migrated.SelectionSummary?.VirtualKey);
        Assert.Equal(InteractiveHotkeySettingsDocument.AgentComposeDefault, migrated.AgentCompose);
        Assert.Equal(migrated, await fixture.Store.LoadAsync(CancellationToken.None));
    }

    [Fact]
    public async Task Schema5_ctrl_shift_factory_defaults_migrate_to_alt_shift_set()
    {
        using var fixture = new Fixture();
        // Schema 5: Ctrl+Shift+A / Ctrl+Shift+V factory; selection unbound.
        fixture.ReplaceJson("""
            {"schemaVersion":5,"selectionTranslation":null,"selectionSummary":null,"agentCompose":null,"screenshot":{"virtualKey":65,"scanCode":30,"modifiers":3,"isExtended":false},"selectionAskAi":null,"clipboardImageOcr":{"virtualKey":86,"scanCode":47,"modifiers":3,"isExtended":false}}
            """);

        var migrated = await fixture.Store.LoadAsync(CancellationToken.None);

        Assert.Equal(InteractiveHotkeySettingsDocument.CurrentSchemaVersion, migrated.SchemaVersion);
        Assert.Equal(InteractiveHotkeySettingsDocument.Default, migrated);
        Assert.Equal(
            InteractiveHotkeySettingsDocument.AltShiftModifiers,
            migrated.Screenshot!.Modifiers);
        Assert.DoesNotContain(
            new[]
            {
                migrated.Screenshot,
                migrated.ClipboardImageOcr,
                migrated.SelectionTranslation,
                migrated.SelectionSummary,
                migrated.AgentCompose,
                migrated.SelectionAskAi,
            },
            binding => binding is { Modifiers: InteractiveHotkeySettingsDocument.CtrlShiftModifiers });
        Assert.Equal(migrated, await fixture.Store.LoadAsync(CancellationToken.None));
    }

    [Fact]
    public async Task Schema5_custom_non_factory_bindings_are_preserved()
    {
        using var fixture = new Fixture();
        // Custom Ctrl+Shift+S screenshot (not factory A) and custom Alt+Shift+Q translation.
        fixture.ReplaceJson("""
            {"schemaVersion":5,"selectionTranslation":{"virtualKey":81,"scanCode":16,"modifiers":6,"isExtended":false},"selectionSummary":null,"agentCompose":null,"screenshot":{"virtualKey":83,"scanCode":31,"modifiers":3,"isExtended":false},"selectionAskAi":null,"clipboardImageOcr":{"virtualKey":86,"scanCode":47,"modifiers":3,"isExtended":false}}
            """);

        var migrated = await fixture.Store.LoadAsync(CancellationToken.None);

        Assert.Equal(InteractiveHotkeySettingsDocument.CurrentSchemaVersion, migrated.SchemaVersion);
        Assert.Equal(0x53u, migrated.Screenshot?.VirtualKey);
        Assert.Equal(InteractiveHotkeySettingsDocument.CtrlShiftModifiers, migrated.Screenshot?.Modifiers);
        Assert.Equal(0x51u, migrated.SelectionTranslation?.VirtualKey);
        Assert.Equal(
            InteractiveHotkeySettingsDocument.ClipboardImageOcrDefault,
            migrated.ClipboardImageOcr);
        Assert.Equal(
            InteractiveHotkeySettingsDocument.SelectionSummaryDefault,
            migrated.SelectionSummary);
    }

    [Fact]
    public async Task Unsupported_schema_or_invalid_binding_fails_closed()
    {
        using var fixture = new Fixture();
        fixture.ReplaceJson("""
            {"schemaVersion":99,"selectionTranslation":null,"selectionSummary":null,"agentCompose":null}
            """);
        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await fixture.Store.LoadAsync(CancellationToken.None));

        fixture.ReplaceJson("""
            {"schemaVersion":2,"screenshot":null,"selectionTranslation":{"virtualKey":74,"scanCode":36,"modifiers":128,"isExtended":false},"selectionSummary":null,"agentCompose":null}
            """);
        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await fixture.Store.LoadAsync(CancellationToken.None));
    }

    private sealed class Fixture : IDisposable
    {
        private readonly TemporaryDirectory directory = new();

        public Fixture()
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.db");
            new VoxFlowDatabaseMigrator().Migrate(databasePath);
            Runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(databasePath, pooling: false));
            Store = new SqliteInteractiveHotkeySettingsStore(Runner);
        }

        public SqliteTransactionRunner Runner { get; }

        public SqliteInteractiveHotkeySettingsStore Store { get; }

        public int CountRows() => Runner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT COUNT(*) FROM settings WHERE key = 'interactive.hotkeys';";
            return Convert.ToInt32(
                command.ExecuteScalar(),
                System.Globalization.CultureInfo.InvariantCulture);
        });

        public void ReplaceJson(string json) => Runner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ('interactive.hotkeys', $json, 0) " +
                "ON CONFLICT(key) DO UPDATE SET json_value = excluded.json_value;";
            command.Parameters.AddWithValue("$json", json);
            _ = command.ExecuteNonQuery();
            return 0;
        });

        public void Dispose()
        {
            Runner.Dispose();
            directory.Dispose();
        }
    }
}
