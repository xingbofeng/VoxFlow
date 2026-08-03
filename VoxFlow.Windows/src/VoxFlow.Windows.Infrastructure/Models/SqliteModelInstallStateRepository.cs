using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;

namespace VoxFlow.Windows.Infrastructure.Models;

public sealed class SqliteModelInstallStateRepository : IModelInstallStateRepository
{
    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteModelInstallStateRepository(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<ModelInstallRecord?> LoadAsync(
        string modelId,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelId);
        cancellationToken.ThrowIfCancellationRequested();
        var value = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT version, state, bytes, total_bytes, install_path, error_code " +
                "FROM models WHERE model_id = $modelId;";
            command.Parameters.AddWithValue("$modelId", modelId);
            using var reader = command.ExecuteReader();
            if (!reader.Read())
            {
                return null;
            }

            if (!Enum.TryParse<ModelInstallPhase>(reader.GetString(1), out var phase))
            {
                throw new InvalidDataException("Stored model phase is invalid.");
            }

            var bytes = reader.GetInt64(2);
            return new ModelInstallRecord(
                modelId,
                reader.GetString(0),
                phase,
                bytes,
                reader.GetInt64(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5));
        });
        return ValueTask.FromResult(value);
    }

    public ValueTask SaveAsync(
        ModelInstallRecord state,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(state);
        cancellationToken.ThrowIfCancellationRequested();
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO models(model_id, version, state, bytes, total_bytes, install_path, error_code, updated_at_unix_ms) " +
                "VALUES ($modelId, $version, $state, $bytes, $totalBytes, $installPath, $errorCode, $updatedAt) " +
                "ON CONFLICT(model_id) DO UPDATE SET " +
                "version = excluded.version, state = excluded.state, bytes = excluded.bytes, " +
                "total_bytes = excluded.total_bytes, " +
                "install_path = excluded.install_path, error_code = excluded.error_code, " +
                "updated_at_unix_ms = excluded.updated_at_unix_ms;";
            command.Parameters.AddWithValue("$modelId", state.ModelId);
            command.Parameters.AddWithValue("$version", state.Version);
            command.Parameters.AddWithValue("$state", state.Phase.ToString());
            command.Parameters.AddWithValue("$bytes", state.BytesDownloaded);
            command.Parameters.AddWithValue("$totalBytes", state.TotalBytes);
            command.Parameters.AddWithValue("$installPath", (object?)state.InstallPath ?? DBNull.Value);
            command.Parameters.AddWithValue("$errorCode", (object?)state.ErrorCode ?? DBNull.Value);
            command.Parameters.AddWithValue(
                "$updatedAt",
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            _ = command.ExecuteNonQuery();
            return 0;
        });
        return ValueTask.CompletedTask;
    }

    public ValueTask DeleteAsync(string modelId, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelId);
        cancellationToken.ThrowIfCancellationRequested();
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM models WHERE model_id = $modelId;";
            command.Parameters.AddWithValue("$modelId", modelId);
            _ = command.ExecuteNonQuery();
            return 0;
        });
        return ValueTask.CompletedTask;
    }
}
