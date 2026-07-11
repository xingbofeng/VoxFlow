namespace VoxFlow.Windows.Application.Credentials;

public sealed class CredentialUnavailableException : Exception
{
    public CredentialUnavailableException()
        : base("The saved credential is unavailable. Delete it and save it again.")
    {
    }

    public override string ToString() => $"{GetType().FullName}: {Message}";
}
