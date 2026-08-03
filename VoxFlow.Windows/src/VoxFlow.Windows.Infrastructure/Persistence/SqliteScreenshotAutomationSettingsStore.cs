using System.Text.Json;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteScreenshotAutomationSettingsStore
    : IScreenshotAutomationSettingsStore
{
    private const string SettingsKey = "screenshot.automation";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteScreenshotAutomationSettingsStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<ScreenshotAutomationSettings> LoadAsync(
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            return command.ExecuteScalar() as string;
        });
        if (json is null)
        {
            return ValueTask.FromResult(ScreenshotAutomationSettings.Default);
        }

        try
        {
            var settings = JsonSerializer.Deserialize<ScreenshotAutomationSettings>(json, JsonOptions);
            return ValueTask.FromResult(settings is { IsValid: true }
                ? settings
                : ScreenshotAutomationSettings.Default);
        }
        catch (JsonException)
        {
            return ValueTask.FromResult(ScreenshotAutomationSettings.Default);
        }
    }

    public ValueTask SaveAsync(
        ScreenshotAutomationSettings settings,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(settings);
        cancellationToken.ThrowIfCancellationRequested();
        if (!settings.IsValid)
        {
            throw new ArgumentException("Current screenshot automation settings are required.", nameof(settings));
        }
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) VALUES ($key, $json, $updatedAt) " +
                "ON CONFLICT(key) DO UPDATE SET json_value = excluded.json_value, " +
                "updated_at_unix_ms = excluded.updated_at_unix_ms;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            command.Parameters.AddWithValue("$json", json);
            command.Parameters.AddWithValue("$updatedAt", timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            _ = command.ExecuteNonQuery();
            return 0;
        });
        return ValueTask.CompletedTask;
    }
}
