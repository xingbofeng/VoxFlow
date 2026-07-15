using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.FileTranscription;

public partial class FileTranscriptionView : System.Windows.Controls.UserControl
{
    private readonly DispatcherTimer refreshTimer = new()
    {
        Interval = TimeSpan.FromMilliseconds(500),
    };

    public FileTranscriptionView()
    {
        InitializeComponent();
        refreshTimer.Tick += (_, _) => ViewModel?.Refresh();
    }

    private FileTranscriptionPageViewModel? ViewModel =>
        DataContext as FileTranscriptionPageViewModel;

    private void OnBrowseFiles(object sender, RoutedEventArgs e)
    {
        if (DataContext is not FileTranscriptionPageViewModel viewModel)
        {
            return;
        }
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            CheckFileExists = true,
            Multiselect = true,
            Filter = $"{L10n.Localize("FileTranscriptionFileDialogFilter")}|*.mp3;*.wav;*.m4a;*.aac;*.mp4;*.mov",
        };
        if (dialog.ShowDialog() == true)
        {
            _ = viewModel.ImportFiles(dialog.FileNames, startImmediately: false);
        }
        e.Handled = true;
    }

    private void OnBrowseFiles(object sender, MouseButtonEventArgs e)
    {
        OnBrowseFiles(sender, new RoutedEventArgs());
        e.Handled = true;
    }

    private void OnFilesDropped(object sender, System.Windows.DragEventArgs e)
    {
        if (DataContext is FileTranscriptionPageViewModel viewModel
            && e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)
            && e.Data.GetData(System.Windows.DataFormats.FileDrop) is string[] paths)
        {
            _ = viewModel.ImportFiles(paths, startImmediately: true);
        }
        e.Handled = true;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        ViewModel?.Refresh();
        refreshTimer.Start();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e) => refreshTimer.Stop();

    private void OnStart(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        ViewModel?.StartSelected();
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        ViewModel?.CancelSelected();
    }

    private void OnContinue(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        ViewModel?.ContinueSelected();
    }

    private void OnRetry(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        ViewModel?.RetrySelected();
    }

    private void OnCopy(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        ViewModel?.CopySelected();
    }

    private async void OnTogglePlayback(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            SelectSenderJob(sender);
            try
            {
                await viewModel.TogglePlaybackSelectedAsync(CancellationToken.None);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                viewModel.ReportActionFailure(
                    "FileTranscriptionFeedbackPlaybackFailed");
            }
        }
    }

    private async void OnDelete(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        if (ViewModel is not { SelectedItem: not null } viewModel) return;
        var confirmed = VoxFlowDialogWindow.ShowConfirm(
            Window.GetWindow(this),
            L10n.Localize("FileTranscriptionDeleteConfirmTitle"),
            L10n.Localize("FileTranscriptionDeleteConfirmMessage"),
            L10n.Localize("FileTranscriptionActionDelete"));
        if (!confirmed) return;
        try
        {
            await viewModel.DeleteSelectedAsync(CancellationToken.None);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            viewModel.ReportActionFailure("FileTranscriptionFeedbackDeleteFailed");
        }
    }

    private void OnExport(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        if (sender is not System.Windows.Controls.Button button) return;
        var menu = new System.Windows.Controls.ContextMenu();
        AddExportItem(menu, "FileTranscriptionExportText", FileTranscriptionExportFormat.Text);
        AddExportItem(menu, "FileTranscriptionExportMarkdown", FileTranscriptionExportFormat.Markdown);
        AddExportItem(menu, "FileTranscriptionExportSrt", FileTranscriptionExportFormat.Srt);
        AddExportItem(menu, "FileTranscriptionExportTranslatedText", FileTranscriptionExportFormat.TranslatedText);
        AddExportItem(menu, "FileTranscriptionExportTranslatedMarkdown", FileTranscriptionExportFormat.TranslatedMarkdown);
        AddExportItem(menu, "FileTranscriptionExportBilingualMarkdown", FileTranscriptionExportFormat.BilingualMarkdown);
        menu.PlacementTarget = button;
        menu.IsOpen = true;
    }

    private void AddExportItem(
        System.Windows.Controls.ContextMenu menu,
        string labelKey,
        FileTranscriptionExportFormat format)
    {
        var item = new System.Windows.Controls.MenuItem
        {
            Header = L10n.Localize(labelKey),
            Tag = format,
        };
        item.Click += OnExportFormat;
        menu.Items.Add(item);
    }

    private async void OnExportFormat(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.MenuItem { Tag: FileTranscriptionExportFormat format }
            && ViewModel is { } viewModel)
        {
            try
            {
                await viewModel.ExportSelectedAsync(format, CancellationToken.None);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                viewModel.ReportActionFailure("FileTranscriptionFeedbackExportFailed");
            }
        }
    }

    private async void OnTranslate(object sender, RoutedEventArgs e)
    {
        SelectSenderJob(sender);
        if (ViewModel is not { } viewModel) return;
        var target = CultureInfo.CurrentUICulture.Name;
        if (string.IsNullOrWhiteSpace(target)) target = "en";
        try
        {
            await viewModel.TranslateSelectedAsync(target, CancellationToken.None);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            viewModel.ReportActionFailure(
                "FileTranscriptionFeedbackTranslationFailed");
        }
    }

    private void SelectSenderJob(object sender)
    {
        if (sender is FrameworkElement
            {
                DataContext: FileTranscriptionJobPresentation item,
            }
            && ViewModel is not null)
        {
            ViewModel.SelectedItem = item;
        }
    }
}
