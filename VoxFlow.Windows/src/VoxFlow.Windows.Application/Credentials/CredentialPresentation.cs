namespace VoxFlow.Windows.Application.Credentials;

public enum CredentialAvailability
{
    Missing,
    Available,
    Unavailable,
}

public sealed record CredentialPresentation(
    CredentialAvailability Availability,
    string Mask)
{
    public override string ToString() =>
        $"CredentialPresentation {{ Availability = {Availability}, Secret = [REDACTED] }}";
}
