using System.Runtime.CompilerServices;
using System.Windows.Automation;
using System.Windows.Controls;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.Application.SelectionTransform;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class AccessibilityContractTests
{
    [Fact]
    public async Task Selection_result_actions_have_localized_accessible_names_and_tab_order()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new SelectionResultWindow();

            var close = Assert.IsType<Button>(window.FindName("CloseButton"));
            var source = Assert.IsType<Button>(window.FindName("SourceTabButton"));
            var result = Assert.IsType<Button>(window.FindName("ResultTabButton"));
            var copy = Assert.IsType<Button>(window.FindName("CopyButton"));

            Assert.Equal(L10n.HistoryDetailClose, AutomationProperties.GetName(close));
            Assert.Equal(L10n.SelectionResultSource, AutomationProperties.GetName(source));
            Assert.Equal(L10n.SelectionResultResult, AutomationProperties.GetName(result));
            Assert.Equal(L10n.SelectionResultCopy, AutomationProperties.GetName(copy));
            Assert.True(close.TabIndex < source.TabIndex);
            Assert.True(source.TabIndex < result.TabIndex);
            Assert.True(result.TabIndex < copy.TabIndex);

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Agent_capable_hud_announces_status_changes_politely()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new HudWindow();
            var capsule = Assert.IsType<Border>(window.FindName("Capsule"));

            Assert.Equal(AutomationLiveSetting.Polite, AutomationProperties.GetLiveSetting(capsule));

            window.Close();
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Translation_and_summary_result_windows_measure_with_real_theme_resources()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            foreach (var operation in Enum.GetValues<SelectionTransformOperation>())
            {
                var viewModel = new SelectionResultViewModel(
                    "selected text",
                    operation,
                    new IdleSelectionTransformService());
                var window = new SelectionResultWindow { DataContext = viewModel };
                var content = Assert.IsAssignableFrom<System.Windows.FrameworkElement>(window.Content);
                content.Resources.MergedDictionaries.Add(
                    ThemeResourceLoader.Load(AppThemeMode.Light));

                content.Measure(new System.Windows.Size(440, 560));
                content.Arrange(new System.Windows.Rect(0, 0, 440, 560));
                content.UpdateLayout();

                Assert.True(content.IsMeasureValid);
                Assert.Equal(
                    viewModel.OperationLabel,
                    AutomationProperties.GetName(
                        Assert.IsType<Border>(window.FindName("Root"))));
                window.Close();
            }

            return Task.CompletedTask;
        });
    }

    private sealed class IdleSelectionTransformService : ISelectionTransformStreamingService
    {
        public async IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
            SelectionTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            _ = request;
            cancellationToken.ThrowIfCancellationRequested();
            await Task.CompletedTask;
            yield break;
        }
    }
}
