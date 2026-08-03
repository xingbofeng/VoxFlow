using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Dialogs;

/// <summary>
/// Modal LLM provider add/edit sheet matching the macOS provider editor
/// (template chips, API-key eye toggle, get-key link, model refresh/add, enable, footer).
/// </summary>
public partial class LlmProviderEditorDialogWindow : Window
{
    private double? ownerOpacity;
    private bool syncingPassword;

    public LlmProviderEditorDialogWindow(
        Window? owner,
        LlmProviderSettingsViewModel host)
    {
        InitializeComponent();
        Owner = owner;
        Host = host ?? throw new ArgumentNullException(nameof(host));
        DataContext = host;
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    public LlmProviderSettingsViewModel Host { get; }

    public string? CapturedApiKey { get; private set; }

    private LlmProviderEditorViewModel? Editor => Host.Editor;

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (Owner is not null)
        {
            ownerOpacity = Owner.Opacity;
            Owner.Opacity = 0.72;
        }

        SyncPasswordFromDraft();
        if (ApiKeyPasswordBox.IsVisible)
        {
            ApiKeyPasswordBox.Focus();
        }
        else
        {
            ApiKeyPlainBox.Focus();
        }
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        if (Owner is not null && ownerOpacity is { } opacity)
        {
            Owner.Opacity = opacity;
        }
    }

    private void OnTemplateSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is not System.Windows.Controls.ComboBox { SelectedValue: string templateId }
            || Editor is null
            || string.Equals(Editor.TemplateId, templateId, StringComparison.Ordinal))
        {
            return;
        }

        try
        {
            Host.ApplyTemplate(templateId);
            ClearApiKeyFields();
        }
        catch
        {
            Host.ReportUiFailure();
        }
    }

    private async void OnRefreshModels(object sender, RoutedEventArgs e)
    {
        try
        {
            await Host.RefreshModelsAsync(CancellationToken.None);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            Host.ReportUiFailure();
        }
    }

    private void OnAddModel(object sender, RoutedEventArgs e)
    {
        Editor?.AddCurrentModelToOptions();
    }

    private async void OnToggleApiKeyVisibility(object sender, RoutedEventArgs e)
    {
        if (Editor is null)
        {
            return;
        }

        if (Editor.IsApiKeyVisible)
        {
            // Hide: keep draft in the password box.
            Editor.IsApiKeyVisible = false;
            SyncPasswordFromDraft();
            return;
        }

        // Show: pull from password box, then optionally load the saved key.
        Editor.DraftApiKey = ApiKeyPasswordBox.Password;
        if (Editor.CanUseSavedCredential
            && string.IsNullOrEmpty(Editor.DraftApiKey)
            && string.IsNullOrEmpty(Editor.RevealedApiKey))
        {
            try
            {
                await Host.RevealApiKeyAsync(CancellationToken.None);
                if (!string.IsNullOrEmpty(Editor.RevealedApiKey))
                {
                    Editor.DraftApiKey = Editor.RevealedApiKey;
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                Host.ReportUiFailure();
                return;
            }
        }

        Editor.IsApiKeyVisible = true;
    }

    private void OnOpenApiKeyHelp(object sender, RoutedEventArgs e)
    {
        var uri = Editor?.ApiKeyUri;
        if (uri is null)
        {
            return;
        }

        try
        {
            _ = Process.Start(new ProcessStartInfo(uri.AbsoluteUri)
            {
                UseShellExecute = true,
            });
        }
        catch
        {
            Host.ReportUiFailure();
        }
    }

    private void OnApiKeyPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (syncingPassword || Editor is null)
        {
            return;
        }

        Editor.DraftApiKey = ApiKeyPasswordBox.Password;
    }

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        if (Editor is null)
        {
            return;
        }

        var apiKey = Editor.IsApiKeyVisible
            ? Editor.DraftApiKey
            : ApiKeyPasswordBox.Password;
        CapturedApiKey = apiKey;
        try
        {
            await Host.SaveEditorAsync(apiKey, CancellationToken.None);
            if (Host.Editor is null)
            {
                DialogResult = true;
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            Host.ReportUiFailure();
        }
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        Host.CancelEditor();
        DialogResult = false;
    }

    private void SyncPasswordFromDraft()
    {
        if (Editor is null)
        {
            return;
        }

        syncingPassword = true;
        try
        {
            ApiKeyPasswordBox.Password = Editor.DraftApiKey ?? string.Empty;
        }
        finally
        {
            syncingPassword = false;
        }
    }

    private void ClearApiKeyFields()
    {
        if (Editor is not null)
        {
            Editor.DraftApiKey = string.Empty;
            Editor.IsApiKeyVisible = false;
            Editor.RevealedApiKey = null;
        }

        syncingPassword = true;
        try
        {
            ApiKeyPasswordBox.Clear();
        }
        finally
        {
            syncingPassword = false;
        }
    }

    /// <summary>
    /// Shows the add/edit sheet. Returns true when the provider was saved.
    /// </summary>
    public static bool? Show(
        Window? owner,
        LlmProviderSettingsViewModel host)
    {
        ArgumentNullException.ThrowIfNull(host);
        if (host.Editor is null)
        {
            throw new InvalidOperationException(
                "BeginAdd or BeginEdit must run before showing the editor dialog.");
        }

        // Clear reveal state so edit opens with a masked key (mac parity).
        host.Editor.IsApiKeyVisible = false;
        host.Editor.RevealedApiKey = null;
        host.Editor.DraftApiKey = string.Empty;

        var dialog = new LlmProviderEditorDialogWindow(owner, host);
        return dialog.ShowDialog();
    }
}
