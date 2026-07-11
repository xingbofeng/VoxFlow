namespace VoxFlow.Windows.Testing;

public static class TestDoubleNamingPolicy
{
    public static bool IsAllowed(Type type)
    {
        ArgumentNullException.ThrowIfNull(type);

        return type.Name.StartsWith("Fake", StringComparison.Ordinal)
            || type.Name.StartsWith("Capturing", StringComparison.Ordinal);
    }
}
