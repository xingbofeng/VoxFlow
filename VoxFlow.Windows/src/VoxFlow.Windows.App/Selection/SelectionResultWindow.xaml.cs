using System.Windows;
using System.Windows.Input;

namespace VoxFlow.Windows.App.Selection;

/// <summary>
/// Focusable floating shell for selection work. It deliberately stays out of
/// taskbar/Alt-Tab and owns only window chrome; the result content and actions
/// are supplied by the presentation layer.
/// </summary>
public partial class SelectionResultWindow : Window
{
    private readonly SelectionSpeechController speech = new(new WindowsSystemSpeechBackend());
    private int speechGeneration;

    public SelectionResultWindow()
    {
        InitializeComponent();
        Closed += OnClosed;
    }

    public void ApplyPlacement(SelectionWindowPlacement placement)
    {
        ArgumentNullException.ThrowIfNull(placement);
        Left = placement.Left;
        Top = placement.Top;
        Width = placement.Width;
        Height = placement.Height;
    }

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (eventArgs.Key != Key.Escape)
        {
            return;
        }

        eventArgs.Handled = true;
        Close();
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs)
    {
        if (eventArgs.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void OnClose(object sender, RoutedEventArgs eventArgs) => Close();

    private void OnSelectSource(object sender, RoutedEventArgs eventArgs)
    {
        StopSpeech(showFeedback: true);
        ViewModel?.SelectTab(SelectionResultTab.Source);
    }

    private void OnSelectResult(object sender, RoutedEventArgs eventArgs)
    {
        StopSpeech(showFeedback: true);
        ViewModel?.SelectTab(SelectionResultTab.Result);
    }

    private void OnCopy(object sender, RoutedEventArgs eventArgs) =>
        _ = ViewModel?.CopyDisplayedText();

    private async void OnReplace(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.ReplaceDisplayedTextAsync();
        }
    }

    private async void OnInsertAfter(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.InsertAfterDisplayedTextAsync();
        }
    }

    private async void OnSpeak(object sender, RoutedEventArgs eventArgs)
    {
        if (ViewModel is not { } viewModel)
        {
            return;
        }

        if (speech.State == SelectionSpeechState.Speaking)
        {
            StopSpeech(showFeedback: true);
            return;
        }

        if (viewModel.DisplayedText is not { Length: > 0 } text)
        {
            return;
        }

        var currentGeneration = Interlocked.Increment(ref speechGeneration);
        var speaking = speech.SpeakAsync(text);
        viewModel.ReportSpeechState(speech.State);
        await speaking;
        if (currentGeneration == Volatile.Read(ref speechGeneration))
        {
            viewModel.ReportSpeechState(speech.State);
        }
    }

    private SelectionResultViewModel? ViewModel => DataContext as SelectionResultViewModel;

    private void StopSpeech(bool showFeedback)
    {
        if (speech.State != SelectionSpeechState.Speaking)
        {
            return;
        }

        Interlocked.Increment(ref speechGeneration);
        speech.Stop();
        if (showFeedback)
        {
            ViewModel?.ReportSpeechState(SelectionSpeechState.Idle, userStopped: true);
        }
    }

    private async void OnClosed(object? sender, EventArgs eventArgs)
    {
        Interlocked.Increment(ref speechGeneration);
        ViewModel?.Dispose();
        await speech.DisposeAsync();
    }
}
