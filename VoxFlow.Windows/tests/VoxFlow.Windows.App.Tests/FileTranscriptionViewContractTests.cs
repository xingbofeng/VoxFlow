using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class FileTranscriptionViewContractTests
{
    [Fact]
    public async Task Workbench_matches_queue_detail_status_and_result_action_contract()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var view = CreateView(Job(FileTranscriptionJobStatus.PartiallyFailed));
            Layout(view);

            var workbench = Assert.IsType<Border>(view.FindName("MainWorkbench"));
            var queue = Assert.IsType<ListBox>(view.FindName("TranscriptionQueue"));
            var result = Assert.IsType<Grid>(view.FindName("ResultPanel"));
            var status = Assert.IsType<Border>(view.FindName("StatusBar"));
            Assert.Equal(520, workbench.ActualHeight);
            Assert.Equal(380, Assert.IsType<Grid>(workbench.Child).ColumnDefinitions[0].ActualWidth);
            Assert.Equal(366, queue.ActualWidth);
            Assert.True(result.ActualWidth > 400);
            Assert.True(status.ActualWidth > 900);

            var buttons = Descendants<Button>(view).ToArray();
            AssertButton(buttons, view.DataContextAs<FileTranscriptionPageViewModel>().ContinueLabel, true);
            AssertButton(buttons, view.DataContextAs<FileTranscriptionPageViewModel>().RetryLabel, true);
            AssertButton(buttons, view.DataContextAs<FileTranscriptionPageViewModel>().DeleteLabel, true);
            AssertButton(buttons, view.DataContextAs<FileTranscriptionPageViewModel>().CopyLabel, true);
            AssertButton(buttons, view.DataContextAs<FileTranscriptionPageViewModel>().ExportLabel, true);
            AssertButton(buttons, view.DataContextAs<FileTranscriptionPageViewModel>().TranslateLabel, true);
            Assert.Contains(Descendants<Expander>(view), expander => expander.Visibility == Visibility.Visible);
            Assert.Equal(2, Descendants<TextBox>(view).Count(textBox => textBox.Visibility == Visibility.Visible));
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Empty_result_actions_expose_disabled_reason_and_error_status_is_live()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var view = CreateView(Job(FileTranscriptionJobStatus.Queued));
            var viewModel = view.DataContextAs<FileTranscriptionPageViewModel>();
            viewModel.ImportFiles([@"C:\Media\unsupported.txt"], startImmediately: false);
            Layout(view);

            foreach (var button in Descendants<Button>(view))
            {
                Assert.False(string.IsNullOrWhiteSpace(AutomationProperties.GetName(button)));
                Assert.True(button.Focusable);
                if (!button.IsEnabled)
                {
                    Assert.False(string.IsNullOrWhiteSpace(
                        AutomationProperties.GetHelpText(button)));
                }
            }

            var liveStatus = Descendants<TextBlock>(view).Single(text =>
                text.Text == viewModel.Status
                && AutomationProperties.GetLiveSetting(text) == AutomationLiveSetting.Polite);
            Assert.Equal(viewModel.LastError, liveStatus.Text);
            Assert.True(Assert.IsType<ListBox>(view.FindName("TranscriptionQueue")).Focusable);
            return Task.CompletedTask;
        });
    }

    private static FileTranscriptionView CreateView(FileTranscriptionJob job)
    {
        var repository = new ViewJobRepository(job);
        var viewModel = new FileTranscriptionPageViewModel(
            "File transcription",
            "Turn files into text",
            repository,
            queue: null,
            () => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B),
            () => RecognitionLanguage.Automatic,
            TimeProvider.System);
        var view = new FileTranscriptionView
        {
            DataContext = viewModel,
            Width = 1040,
            Height = 720,
        };
        view.Resources.MergedDictionaries.Add(ThemeResourceLoader.Load(AppThemeMode.Light));
        return view;
    }

    private static void Layout(FrameworkElement element)
    {
        element.Measure(new Size(element.Width, element.Height));
        element.Arrange(new Rect(0, 0, element.Width, element.Height));
        element.UpdateLayout();
    }

    private static void AssertButton(
        IReadOnlyCollection<Button> buttons,
        string label,
        bool isEnabled)
    {
        var button = Assert.Single(buttons, candidate =>
            Equals(candidate.Content, label)
            && candidate.Visibility == Visibility.Visible);
        Assert.Equal(isEnabled, button.IsEnabled);
    }

    private static IEnumerable<T> Descendants<T>(DependencyObject root)
        where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match) yield return match;
            foreach (var descendant in Descendants<T>(child)) yield return descendant;
        }
    }

    private static FileTranscriptionJob Job(FileTranscriptionJobStatus status) => new(
        "job-1",
        Path.GetTempFileName(),
        "meeting.mp4",
        AsrProviderId.Qwen,
        RecognitionLanguage.Automatic,
        1,
        status: status,
        durationMs: 60_000,
        progress: status == FileTranscriptionJobStatus.PartiallyFailed ? 0.5 : 0,
        finalText: status == FileTranscriptionJobStatus.PartiallyFailed ? "original text" : null,
        segmentCount: 2,
        segmentCompleted: status == FileTranscriptionJobStatus.PartiallyFailed ? 1 : 0,
        translationStatus: status == FileTranscriptionJobStatus.PartiallyFailed
            ? FileTranscriptionTranslationStatus.Completed
            : FileTranscriptionTranslationStatus.NotRequested,
        translatedText: status == FileTranscriptionJobStatus.PartiallyFailed
            ? "translated text"
            : null,
        translationTargetLanguage: status == FileTranscriptionJobStatus.PartiallyFailed
            ? "zh-Hans"
            : null);

    private sealed class ViewJobRepository(params FileTranscriptionJob[] initial)
        : IFileTranscriptionJobRepository
    {
        private readonly List<FileTranscriptionJob> jobs = [.. initial];
        public void Create(FileTranscriptionJob job) => jobs.Add(job);
        public FileTranscriptionJob? Get(string id) => jobs.SingleOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs.ToArray();
        public bool Update(FileTranscriptionJob job) => false;
        public bool Delete(string id) => false;
        public int MarkRunningAsInterrupted() => 0;
    }
}

internal static class FileTranscriptionViewTestExtensions
{
    public static T DataContextAs<T>(this FrameworkElement element) where T : class =>
        Assert.IsType<T>(element.DataContext);
}
