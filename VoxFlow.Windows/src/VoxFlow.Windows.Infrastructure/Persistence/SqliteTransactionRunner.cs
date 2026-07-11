using Microsoft.Data.Sqlite;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteTransactionRunner : IDisposable
{
    private readonly SqliteConnectionFactory connectionFactory;
    private readonly object synchronization = new();
    private bool disposed;

    public SqliteTransactionRunner(SqliteConnectionFactory connectionFactory)
    {
        this.connectionFactory = connectionFactory
            ?? throw new ArgumentNullException(nameof(connectionFactory));
    }

    public TResult Read<TResult>(Func<SqliteConnection, TResult> operation)
    {
        ArgumentNullException.ThrowIfNull(operation);

        lock (synchronization)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            using var connection = connectionFactory.OpenConnection();
            return operation(connection);
        }
    }

    public TResult Write<TResult>(
        Func<SqliteConnection, SqliteTransaction, TResult> operation)
    {
        ArgumentNullException.ThrowIfNull(operation);

        lock (synchronization)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            using var connection = connectionFactory.OpenConnection();
            using var transaction = connection.BeginTransaction();

            try
            {
                var result = operation(connection, transaction);
                transaction.Commit();
                return result;
            }
            catch
            {
                try
                {
                    transaction.Rollback();
                }
                catch (SqliteException)
                {
                    // Keep the callback failure as the observable error.
                }

                throw;
            }
        }
    }

    public void Dispose()
    {
        lock (synchronization)
        {
            disposed = true;
        }
    }
}
