using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.App.Shell;

/// <summary>
/// Read-only projection of the only executable Agent runtime that VoxFlow may
/// launch. The card deliberately receives the verifier result rather than a
/// path, so a settings view can never cause a PATH fallback.
/// </summary>
public sealed class BuiltinAgentSettingsCardViewModel : BindableObject
{
    private readonly ILlmProviderManagementService? providers;
    private LlmProviderRecord? defaultProvider;
    private bool isTesting;

    public BuiltinAgentSettingsCardViewModel(
        BuiltinAgentRuntimeStatus? runtime,
        ILlmProviderManagementService? providers)
    {
        Runtime = runtime;
        this.providers = providers;
        Refresh();
    }

    private BuiltinAgentRuntimeStatus? Runtime { get; }

    private LlmProviderRecord? DefaultProvider => defaultProvider;

    public string Heading => L10n.Localize("SettingsAgentHeading");

    public string Description => L10n.Localize("SettingsAgentDescription");

    public string RuntimeLabel => L10n.Localize("SettingsAgentRuntimeLabel");

    public string RuntimeStatus => L10n.Localize(Runtime?.Availability switch
    {
        BuiltinAgentRuntimeAvailability.Available => "SettingsAgentRuntimeAvailable",
        BuiltinAgentRuntimeAvailability.Missing => "SettingsAgentRuntimeMissing",
        BuiltinAgentRuntimeAvailability.ManifestInvalid => "SettingsAgentRuntimeInvalid",
        BuiltinAgentRuntimeAvailability.HashMismatch => "SettingsAgentRuntimeHashMismatch",
        null => "SettingsAgentRuntimeDisabled",
        _ => throw new ArgumentOutOfRangeException(),
    });

    public string VersionLabel => L10n.Localize("SettingsAgentVersionLabel");

    public string Version => Runtime?.Version ?? L10n.Localize("SettingsAgentNotAvailable");

    public string HashLabel => L10n.Localize("SettingsAgentHashLabel");

    public string Hash => Runtime?.ExpectedSha256
        ?? L10n.Localize("SettingsAgentNotAvailable");

    public string ProviderLabel => L10n.Localize("SettingsAgentProviderLabel");

    public string Provider => DefaultProvider?.DisplayName
        ?? L10n.Localize("SettingsAgentNoDefaultProvider");

    public string ModelLabel => L10n.Localize("SettingsAgentModelLabel");

    public string Model => DefaultProvider?.DefaultModel
        ?? L10n.Localize("SettingsAgentNotAvailable");

    public string ConnectionHealthLabel =>
        L10n.Localize("SettingsAgentConnectionHealthLabel");

    public string ConnectionHealth => DefaultProvider is null
        ? L10n.Localize("SettingsAgentNoDefaultProvider")
        : L10n.Localize(DefaultProvider.HealthStatus switch
        {
            LlmProviderHealthStatus.Unknown => "LlmProviderHealthUnknown",
            LlmProviderHealthStatus.Testing => "LlmProviderHealthTesting",
            LlmProviderHealthStatus.Ok => "LlmProviderHealthAvailable",
            LlmProviderHealthStatus.Error => "LlmProviderHealthUnavailable",
            _ => throw new ArgumentOutOfRangeException(),
        });

    public string ToolCallingHealthLabel =>
        L10n.Localize("SettingsAgentToolCallingHealthLabel");

    public string ToolCallingHealth => DefaultProvider is null
        ? L10n.Localize("SettingsAgentNoDefaultProvider")
        : L10n.Localize(DefaultProvider.AgentCapabilityStatus switch
        {
            LlmAgentCapabilityStatus.Unknown => "LlmProviderAgentUnknown",
            LlmAgentCapabilityStatus.Supported => "LlmProviderAgentSupported",
            LlmAgentCapabilityStatus.Unsupported => "LlmProviderAgentUnsupported",
            LlmAgentCapabilityStatus.Error => "LlmProviderAgentError",
            _ => throw new ArgumentOutOfRangeException(),
        });

    public bool IsRuntimeAvailable => Runtime?.IsAvailable == true;

    public bool IsTesting
    {
        get => isTesting;
        private set
        {
            if (SetField(ref isTesting, value))
            {
                OnPropertyChanged(nameof(CanTest));
            }
        }
    }

    public bool CanTest => IsRuntimeAvailable && DefaultProvider is not null && !IsTesting;

    public void Refresh()
    {
        defaultProvider = providers?.List().FirstOrDefault(provider =>
            provider.IsDefault && provider.Enabled);
        OnPropertyChanged(nameof(Provider));
        OnPropertyChanged(nameof(Model));
        OnPropertyChanged(nameof(ConnectionHealth));
        OnPropertyChanged(nameof(ToolCallingHealth));
        OnPropertyChanged(nameof(CanTest));
    }

    public async Task<bool> TestAsync(CancellationToken cancellationToken)
    {
        if (!CanTest || providers is null || DefaultProvider is null)
        {
            return false;
        }

        IsTesting = true;
        try
        {
            var result = await providers.TestAgentCapabilityAsync(
                DefaultProvider.Id,
                cancellationToken);
            Refresh();
            return result.IsSupported;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            Refresh();
            return false;
        }
        finally
        {
            IsTesting = false;
        }
    }
}
