namespace VoxFlow.Windows.Application.Credentials;

public sealed record CredentialKey
{
    public CredentialKey(string ownerKind, string ownerId, string fieldId)
    {
        OwnerKind = Normalize(ownerKind, nameof(ownerKind));
        OwnerId = Normalize(ownerId, nameof(ownerId));
        FieldId = Normalize(fieldId, nameof(fieldId));
    }

    public string OwnerKind { get; }

    public string OwnerId { get; }

    public string FieldId { get; }

    // Storage schema V001 used field_name. Keep the source-level alias until a
    // later schema cycle can rename that column without breaking old callers.
    public string FieldName => FieldId;

    public override string ToString() =>
        $"CredentialKey {{ OwnerKind = {OwnerKind}, OwnerId = {OwnerId}, FieldId = {FieldId}, Secret = [REDACTED] }}";

    private static string Normalize(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        return value.Trim();
    }
}
