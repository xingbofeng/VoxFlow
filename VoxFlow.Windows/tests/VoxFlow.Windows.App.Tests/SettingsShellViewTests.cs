using System.Windows;
using System.Windows.Controls;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class SettingsShellViewTests
{
    [Fact]
    public async Task Settings_view_uses_a_220_pixel_navigation_and_30_pixel_scrollable_content_inset()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var type = typeof(MainWindow).Assembly.GetType(
                "VoxFlow.Windows.App.Settings.SettingsShellView");
            Assert.NotNull(type);
            var view = Assert.IsAssignableFrom<FrameworkElement>(
                Activator.CreateInstance(type));
            view.ApplyTemplate();

            var layout = Assert.IsType<Grid>(view.FindName("SettingsLayout"));
            Assert.Equal(new GridLength(220), layout.ColumnDefinitions[0].Width);
            var content = Assert.IsType<Border>(view.FindName("SettingsContentHost"));
            Assert.Equal(new Thickness(30), content.Padding);
            Assert.IsType<ScrollViewer>(content.Child);

            return Task.CompletedTask;
        });
    }
}
