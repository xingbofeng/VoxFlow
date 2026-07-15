using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media.Effects;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.App.Localization;
using WpfControl = System.Windows.Controls.Control;
using WpfButton = System.Windows.Controls.Button;

namespace VoxFlow.Windows.App.Composition;

internal sealed class WpfAgentQuestionPresenter : IAgentQuestionPresenter
{
    public Task<IReadOnlyDictionary<string, IReadOnlyList<string>>?> AskAsync(IReadOnlyList<AgentQuestion> questions, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null) return Task.FromResult<IReadOnlyDictionary<string, IReadOnlyList<string>>?>(null);
        var completion = new TaskCompletionSource<IReadOnlyDictionary<string, IReadOnlyList<string>>?>();
        _ = dispatcher.InvokeAsync(() => new AgentQuestionWindow(questions, completion).Show());
        return completion.Task.WaitAsync(cancellationToken);
    }
}

internal sealed class AgentQuestionWindow : Window
{
    private readonly TaskCompletionSource<IReadOnlyDictionary<string, IReadOnlyList<string>>?> completion;
    private readonly List<(AgentQuestion Question, List<(ToggleButton Control, AgentQuestionOption Option)> Options)> choices = [];
    public AgentQuestionWindow(IReadOnlyList<AgentQuestion> questions, TaskCompletionSource<IReadOnlyDictionary<string, IReadOnlyList<string>>?> completion)
    {
        this.completion = completion;
        Title = L10n.Localize("AgentQuestionWindowTitle");
        Width = 540;
        MaxHeight = 720;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = false;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        AutomationProperties.SetName(this, Title);
        PreviewKeyDown += OnPreviewKeyDown;

        var root = new Border
        {
            Margin = new Thickness(16),
            Padding = new Thickness(24),
            CornerRadius = new CornerRadius(14),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect
            {
                BlurRadius = 24,
                Direction = 270,
                ShadowDepth = 6,
                Opacity = 0.22,
                Color = System.Windows.Media.Color.FromArgb(0x66, 0, 0, 0),
            },
        };
        root.SetResourceReference(Border.BackgroundProperty, "PanelBackgroundBrush");
        root.SetResourceReference(Border.BorderBrushProperty, "PanelBorderBrush");
        var layout = new DockPanel();
        root.Child = layout;

        var heading = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        heading.ColumnDefinitions.Add(new ColumnDefinition());
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var headingText = new TextBlock
        {
            Text = Title,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        };
        headingText.SetResourceReference(TextBlock.FontSizeProperty, "TitleFontSize");
        headingText.SetResourceReference(TextBlock.ForegroundProperty, "PrimaryTextBrush");
        heading.Children.Add(headingText);
        var close = new WpfButton
        {
            Content = "×",
            Width = 30,
            Height = 30,
            FontSize = 18,
            Padding = new Thickness(0),
            IsCancel = true,
            TabIndex = 0,
        };
        close.SetResourceReference(WpfControl.StyleProperty, "VoxFlowQuietButtonStyle");
        AutomationProperties.SetName(close, L10n.Localize("AgentQuestionCancel"));
        close.Click += (_, _) => Close();
        Grid.SetColumn(close, 1);
        heading.Children.Add(close);
        DockPanel.SetDock(heading, Dock.Top);
        layout.Children.Add(heading);

        var actions = new StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal, HorizontalAlignment = System.Windows.HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var cancel = new WpfButton { Content = L10n.Localize("AgentQuestionCancel"), MinWidth = 92, IsCancel = true, Margin = new Thickness(0, 0, 8, 0) };
        cancel.SetResourceReference(WpfControl.StyleProperty, "VoxFlowSecondaryButtonStyle");
        AutomationProperties.SetName(cancel, cancel.Content?.ToString() ?? string.Empty);
        cancel.Click += (_, _) => Close();
        var confirm = new WpfButton { Content = L10n.Localize("AgentQuestionContinue"), MinWidth = 92, IsDefault = true };
        AutomationProperties.SetName(confirm, confirm.Content?.ToString() ?? string.Empty);
        confirm.Click += (_, _) => Submit();
        actions.Children.Add(cancel);
        actions.Children.Add(confirm);
        DockPanel.SetDock(actions, Dock.Bottom);
        layout.Children.Add(actions);
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = 550 };
        var body = new StackPanel(); scroll.Content = body; layout.Children.Add(scroll);
        var tabIndex = 0;
        foreach (var question in questions)
        {
            var card = new Border
            {
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14),
                Margin = new Thickness(0, 0, 0, 12),
                BorderThickness = new Thickness(1),
            };
            card.SetResourceReference(Border.BackgroundProperty, "ControlBackgroundBrush");
            card.SetResourceReference(Border.BorderBrushProperty, "PanelBorderBrush");
            var panel = new StackPanel();
            card.Child = panel;
            AutomationProperties.SetName(panel, $"{question.Header}: {question.Question}");
            var header = new TextBlock { Text = question.Header, FontWeight = FontWeights.SemiBold };
            header.SetResourceReference(TextBlock.ForegroundProperty, "AccentDarkBrush");
            panel.Children.Add(header);
            var questionText = new TextBlock { Text = question.Question, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 5, 0, 10) };
            questionText.SetResourceReference(TextBlock.ForegroundProperty, "PrimaryTextBrush");
            panel.Children.Add(questionText);
            var options = new List<(ToggleButton Control, AgentQuestionOption Option)>();
            foreach (var option in question.Options)
            {
                var control = new ToggleButton
                {
                    Content = BuildOptionContent(option),
                    Margin = new Thickness(0, 3, 0, 3),
                    TabIndex = tabIndex++,
                };
                control.SetResourceReference(WpfControl.StyleProperty, "VoxFlowToggleButtonStyle");
                if (!question.MultiSelect)
                {
                    control.Checked += (_, _) =>
                    {
                        foreach (var sibling in options.Where(entry => !ReferenceEquals(entry.Control, control)))
                        {
                            sibling.Control.IsChecked = false;
                        }
                    };
                }
                AutomationProperties.SetName(control, option.Label);
                AutomationProperties.SetHelpText(control, option.Description);
                options.Add((control, option));
                panel.Children.Add(control);
            }
            choices.Add((question, options));
            body.Children.Add(card);
        }
        cancel.TabIndex = tabIndex++;
        confirm.TabIndex = tabIndex;
        Content = root;
        Closed += (_, _) => completion.TrySetResult(null);
        ContentRendered += (_, _) => choices.SelectMany(entry => entry.Options).FirstOrDefault().Control?.Focus();
    }

    private static StackPanel BuildOptionContent(AgentQuestionOption option)
    {
        var content = new StackPanel();
        var label = new TextBlock { Text = option.Label, FontWeight = FontWeights.SemiBold };
        label.SetResourceReference(TextBlock.ForegroundProperty, "PrimaryTextBrush");
        content.Children.Add(label);
        var description = new TextBlock
        {
            Text = option.Description,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 3, 0, 0),
        };
        description.SetResourceReference(TextBlock.ForegroundProperty, "SecondaryTextBrush");
        description.SetResourceReference(TextBlock.FontSizeProperty, "CaptionFontSize");
        content.Children.Add(description);
        if (option.Preview is { Length: > 0 })
        {
            var preview = new TextBlock
            {
                Text = option.Preview,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 6, 0, 0),
                Padding = new Thickness(8, 6, 8, 6),
            };
            preview.SetResourceReference(TextBlock.BackgroundProperty, "PanelBackgroundBrush");
            preview.SetResourceReference(TextBlock.ForegroundProperty, "SecondaryTextBrush");
            preview.SetResourceReference(TextBlock.FontSizeProperty, "CaptionFontSize");
            content.Children.Add(preview);
        }
        return content;
    }

    private void Submit()
    {
        var answers = new Dictionary<string, IReadOnlyList<string>>();
        foreach (var (question, options) in choices)
        {
            var selected = options
                .Where(entry => entry.Control.IsChecked == true)
                .Select(entry => entry.Option.Label)
                .ToArray();
            if (selected.Length == 0) return;
            answers[question.Question] = selected;
        }
        completion.TrySetResult(answers); Close();
    }

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.Escape)
        {
            eventArgs.Handled = true;
            Close();
        }
    }
}
