using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.App.Glossary;

public partial class GlossaryView : System.Windows.Controls.UserControl
{
    private bool loaded;

    public GlossaryView() => InitializeComponent();

    private GlossaryPageViewModel? ViewModel => DataContext as GlossaryPageViewModel;

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (loaded || ViewModel is null)
        {
            return;
        }
        loaded = true;
        await ViewModel.LoadAsync();
    }

    private async void OnAdd(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }
        var owner = Window.GetWindow(this);
        if (GlossaryTabs.SelectedIndex == 0)
        {
            var dialog = new VoxFlowFormDialogWindow(
                owner,
                L10n.Localize("GlossaryAddHotwordTitle"),
                L10n.Localize("GlossaryHotwordLabel"),
                L10n.Localize("GlossaryNoteLabel"));
            if (dialog.ShowDialog() == true)
            {
                await ViewModel.AddHotwordAsync(dialog.PrimaryText, dialog.SecondaryText);
            }
            return;
        }

        var replacementDialog = new VoxFlowFormDialogWindow(
            owner,
            L10n.Localize("GlossaryAddReplacementTitle"),
            L10n.Localize("GlossarySourceLabel"),
            L10n.Localize("GlossaryTargetLabel"),
            L10n.Localize("GlossaryWholeWordLabel"));
        if (replacementDialog.ShowDialog() == true)
        {
            await ViewModel.AddReplacementAsync(
                replacementDialog.PrimaryText,
                replacementDialog.SecondaryText,
                replacementDialog.OptionValue);
        }
    }

    private async void OnDeleteHotword(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null && sender is System.Windows.Controls.Button { Tag: GlossaryHotword item })
        {
            await ViewModel.RemoveHotwordAsync(item);
        }
    }

    private async void OnDeleteReplacement(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null && sender is System.Windows.Controls.Button { Tag: TextReplacementRule item })
        {
            await ViewModel.RemoveReplacementAsync(item);
        }
    }

    private async void OnAddSuggestion(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null && sender is System.Windows.Controls.Button { Tag: string term })
        {
            await ViewModel.AddSuggestionAsync(term);
        }
    }

    private async void OnIgnoreSuggestion(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null && sender is System.Windows.Controls.Button { Tag: string term })
        {
            await ViewModel.IgnoreSuggestionAsync(term);
        }
    }

    private async void OnImport(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = L10n.Localize("GlossaryImportTitle"),
            Filter = L10n.Localize("GlossaryImportFilter"),
            Multiselect = false,
        };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true)
        {
            var lines = await File.ReadAllLinesAsync(dialog.FileName);
            var count = await ViewModel.ImportHotwordsAsync(lines);
            VoxFlowDialogWindow.ShowMessage(
                Window.GetWindow(this),
                L10n.Localize("GlossaryImportCompleteTitle"),
                string.Format(L10n.Localize("GlossaryImportCompleteMessage"), count));
        }
    }

    private async void OnOpenFolder(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow",
            "Exports");
        Directory.CreateDirectory(folder);
        var exportPath = Path.Combine(folder, "glossary.json");
        await File.WriteAllTextAsync(
            exportPath,
            JsonSerializer.Serialize(
                ViewModel.Snapshot(),
                new JsonSerializerOptions(JsonSerializerDefaults.Web) { WriteIndented = true }));
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{exportPath}\"")
        {
            UseShellExecute = true,
        });
    }
}
