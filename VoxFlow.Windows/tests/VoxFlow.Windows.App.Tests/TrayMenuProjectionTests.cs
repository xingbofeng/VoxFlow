using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class TrayMenuProjectionTests
{
    [Fact]
    public void Menu_contains_only_the_approved_language_asr_openai_and_app_actions()
    {
        var menu = TrayMenuProjection.Build(State());

        Assert.Equal(
            [
                "language",
                "asr",
                "openai",
                "separator.providers",
                "app.openWindow",
                "app.openSettings",
                "app.openGithub",
                "app.openPermissions",
                "separator.exit",
                "app.exit",
            ],
            menu.Items.Select(item => item.Id));
        Assert.DoesNotContain(
            menu.Flatten(),
            item => item.Id.Contains("screenshot", StringComparison.OrdinalIgnoreCase)
                || item.Id.Contains("agent", StringComparison.OrdinalIgnoreCase)
                || item.Id.Contains("translation", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Unconfigured_or_unready_choices_are_disabled_while_current_choices_are_checked()
    {
        var menu = TrayMenuProjection.Build(State());

        var selectedLanguage = menu.Find("language.zh-CN");
        Assert.True(selectedLanguage.IsChecked);
        Assert.True(selectedLanguage.IsEnabled);

        var selectedAsr = menu.Find("asr.qwen.0.6b");
        Assert.True(selectedAsr.IsChecked);
        Assert.True(selectedAsr.IsEnabled);

        Assert.False(menu.Find("asr.qwen.1.7b").IsEnabled);
        Assert.False(menu.Find("asr.tencent").IsEnabled);
        Assert.True(menu.Find("asr.aliyun").IsEnabled);
        Assert.False(menu.Find("openai.enabled").IsEnabled);
        Assert.False(menu.Find("openai.enabled").IsChecked);
    }

    [Fact]
    public void Menu_opening_reloads_state_instead_of_reusing_a_stale_projection()
    {
        var source = new MutableTrayMenuStateSource(State());
        var view = new CapturingTrayMenuView();
        var controller = new TrayMenuController(source, view);

        controller.OnMenuOpening();
        Assert.True(view.LastMenu!.Find("asr.qwen.0.6b").IsChecked);

        source.Current = State() with
        {
            Language = RecognitionLanguage.English,
            SelectedAsr = new AsrSelection(AsrProviderId.AliyunDashScope, null),
            OpenAiConfigured = true,
            OpenAiEnabled = true,
        };
        controller.OnMenuOpening();

        Assert.Equal(2, source.ReadCount);
        Assert.True(view.LastMenu!.Find("language.en-US").IsChecked);
        Assert.True(view.LastMenu.Find("asr.aliyun").IsChecked);
        Assert.True(view.LastMenu.Find("openai.enabled").IsEnabled);
        Assert.True(view.LastMenu.Find("openai.enabled").IsChecked);
    }

    private static TrayMenuState State() => new(
        RecognitionLanguage.ChineseMandarin,
        new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B),
        [
            new TrayAsrChoice(AsrProviderId.Qwen, QwenVariant.Qwen06B, IsConfigured: true, IsReady: true),
            new TrayAsrChoice(AsrProviderId.Qwen, QwenVariant.Qwen17B, IsConfigured: true, IsReady: false),
            new TrayAsrChoice(AsrProviderId.TencentCloud, null, IsConfigured: false, IsReady: false),
            new TrayAsrChoice(AsrProviderId.AliyunDashScope, null, IsConfigured: true, IsReady: true),
            new TrayAsrChoice(AsrProviderId.Volcengine, null, IsConfigured: true, IsReady: false),
        ],
        OpenAiConfigured: false,
        OpenAiEnabled: false);

    private sealed class MutableTrayMenuStateSource(TrayMenuState initial) : ITrayMenuStateSource
    {
        public TrayMenuState Current { get; set; } = initial;

        public int ReadCount { get; private set; }

        public TrayMenuState Read()
        {
            ReadCount++;
            return Current;
        }
    }

    private sealed class CapturingTrayMenuView : ITrayMenuView
    {
        public TrayMenuModel? LastMenu { get; private set; }

        public void Render(TrayMenuModel menu) => LastMenu = menu;
    }
}
