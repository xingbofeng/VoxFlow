using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class CloudProviderSettingsPresentationTests
{
    [Fact]
    public void Credential_presentations_survive_reload_as_fixed_masks_without_revealing_values()
    {
        var card = CreateCard();

        card.ApplyCredentialPresentations(
            new CredentialPresentation(CredentialAvailability.Available, "••••••••"),
            new CredentialPresentation(CredentialAvailability.Available, "••••••••"),
            new CredentialPresentation(CredentialAvailability.Available, "••••••••"));

        Assert.Equal("••••••••", card.FirstCredentialPresentation);
        Assert.Equal("••••••••", card.SecondCredentialPresentation);
        Assert.Equal("••••••••", card.ThirdCredentialPresentation);
        Assert.DoesNotContain("secret", card.CredentialSummary, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Operation_state_is_immediate_and_rejects_duplicate_button_actions()
    {
        var card = CreateCard();

        Assert.True(card.TryBeginOperation("SettingsOperationTesting"));
        Assert.True(card.IsBusy);
        Assert.False(card.CanExecuteActions);
        Assert.False(string.IsNullOrWhiteSpace(card.FeedbackMessage));
        Assert.False(card.TryBeginOperation("SettingsOperationSaving"));

        card.CompleteOperation(configured: true, ready: true, "SettingsConnectionSucceeded");

        Assert.False(card.IsBusy);
        Assert.True(card.CanExecuteActions);
        Assert.True(card.IsConfigured);
        Assert.True(card.IsReady);
        Assert.False(string.IsNullOrWhiteSpace(card.FeedbackMessage));
    }

    [Fact]
    public void Failed_operation_restores_buttons_and_exposes_sanitized_feedback()
    {
        var card = CreateCard();
        _ = card.TryBeginOperation("SettingsOperationSaving");

        card.FailOperation();

        Assert.False(card.IsBusy);
        Assert.True(card.CanExecuteActions);
        Assert.False(string.IsNullOrWhiteSpace(card.FeedbackMessage));
        Assert.DoesNotContain("Exception", card.FeedbackMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Selected_ready_card_exposes_in_use_status_and_eye_glyph()
    {
        var card = CreateCard();
        card.Apply(configured: true, ready: true, selected: true);

        Assert.True(card.IsSelected);
        Assert.False(card.CanSelect);
        Assert.True(card.CanRevealSecrets);
        Assert.Equal("👁", card.RevealGlyph);
        Assert.Equal(L10n.Localize("SettingsModelStatusSelected"), card.Status);

        card.SetSecretsVisible(true);
        Assert.Equal("🙈", card.RevealGlyph);
    }

    private static CloudProviderSettingsCardViewModel CreateCard() => new(
        AsrProviderId.TencentCloud,
        "Tencent Cloud",
        "Cloud speech recognition");
}
