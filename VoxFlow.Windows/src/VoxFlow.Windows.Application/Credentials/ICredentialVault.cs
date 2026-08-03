namespace VoxFlow.Windows.Application.Credentials;

public interface ICredentialVault : IDisposable
{
    Task SaveAsync(
        CredentialKey key,
        string secret,
        CancellationToken cancellationToken = default);

    Task<string?> ReadSecretAsync(
        CredentialKey key,
        CancellationToken cancellationToken = default);

    Task<CredentialPresentation> GetPresentationAsync(
        CredentialKey key,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        CredentialKey key,
        CancellationToken cancellationToken = default);

    Task<int> DeleteOwnerAsync(
        string ownerKind,
        string ownerId,
        CancellationToken cancellationToken = default);
}
