namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed record SqliteMigration
{
    public SqliteMigration(long version, string name, string sql)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(version);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentException.ThrowIfNullOrWhiteSpace(sql);

        Version = version;
        Name = name;
        Sql = sql;
    }

    public long Version { get; }

    public string Name { get; }

    public string Sql { get; }
}
