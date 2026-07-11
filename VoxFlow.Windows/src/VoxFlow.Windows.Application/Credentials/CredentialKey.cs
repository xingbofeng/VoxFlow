namespace VoxFlow.Windows.Application.Credentials;

public sealed record CredentialKey
{
    public CredentialKey(string ownerKind, string ownerId, string fieldName)
    {
        OwnerKind = Normalize(ownerKind, nameof(ownerKind));
        OwnerId = Normalize(ownerId, nameof(ownerId));
        FieldName = Normalize(fieldName, nameof(fieldName));
    }

    public string OwnerKind { get; }

    public string OwnerId { get; }

    public string FieldName { get; }

    private static string Normalize(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        return value.Trim();
    }
}
