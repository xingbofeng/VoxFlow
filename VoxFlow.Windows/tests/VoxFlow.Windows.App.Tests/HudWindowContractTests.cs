using System.Windows;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class HudWindowContractTests
{
    [Fact]
    public async Task Hud_window_is_nonactivating_topmost_borderless_and_mouse_transparent()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var window = new HudWindow();

            Assert.Equal(WindowStyle.None, window.WindowStyle);
            Assert.Equal(ResizeMode.NoResize, window.ResizeMode);
            Assert.True(window.Topmost);
            Assert.False(window.ShowInTaskbar);
            Assert.False(window.ShowActivated);
            Assert.True(window.AllowsTransparency);
            Assert.False(window.IsHitTestVisible);
            Assert.Equal(52D, window.MinHeight);
            Assert.Equal(76D, window.MaxHeight);
            Assert.Equal(TimeSpan.FromMilliseconds(350), HudWindow.EntryAnimationDuration);
            Assert.Equal(TimeSpan.FromMilliseconds(220), HudWindow.ExitAnimationDuration);
            Assert.Equal(
                HudWindow.WsExNoActivate
                    | HudWindow.WsExToolWindow
                    | HudWindow.WsExTransparent,
                HudWindow.RequiredExtendedWindowStyles);

            window.Close();
            return Task.CompletedTask;
        });
    }
}
