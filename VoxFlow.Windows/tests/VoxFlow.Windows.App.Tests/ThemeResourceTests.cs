using System.IO;
using System.Windows;
using System.Windows.Media;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ThemeResourceTests
{
    [Fact]
    public async Task Light_and_dark_resources_match_the_approved_AppTheme_palette()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var light = ThemeResourceLoader.Load(AppThemeMode.Light);
            var dark = ThemeResourceLoader.Load(AppThemeMode.Dark);

            AssertColor(light, "PageBackgroundColor", "#FFF6F9F7");
            AssertColor(dark, "PageBackgroundColor", "#FF141816");
            AssertColor(light, "PanelBackgroundColor", "#FFFDFEFD");
            AssertColor(dark, "PanelBackgroundColor", "#FF1F2421");
            AssertColor(light, "ControlBackgroundColor", "#FFF2F5F4");
            AssertColor(dark, "ControlBackgroundColor", "#FF292F2C");
            AssertColor(light, "AccentColor", "#FF0E6B58");
            AssertColor(dark, "AccentColor", "#FF0E6B58");
            AssertColor(light, "SidebarBackgroundColor", "#FFF0F4F2");
            AssertColor(dark, "SidebarBackgroundColor", "#FF181D1B");

            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Shared_resources_pin_spacing_radii_typography_borders_and_shadow_tokens()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var resources = ThemeResourceLoader.Load(AppThemeMode.Light);

            Assert.Equal(28D, resources["PageSpacing"]);
            Assert.Equal(18D, resources["SectionSpacing"]);
            Assert.Equal(12D, resources["GridSpacing"]);
            Assert.Equal(16D, resources["CardSpacing"]);
            Assert.Equal(12D, resources["CardRadius"]);
            Assert.Equal(8D, resources["ControlRadius"]);
            Assert.Equal(10D, resources["RowRadius"]);
            Assert.Equal(1D, resources["PanelBorderWidth"]);
            Assert.Equal(8D, resources["CardShadowBlurRadius"]);
            Assert.Equal(3D, resources["CardShadowOffsetY"]);
            Assert.Equal(0.045D, resources["CardShadowOpacity"]);
            Assert.Equal(24D, resources["HeadingFontSize"]);
            Assert.Equal(18D, resources["TitleFontSize"]);
            Assert.Equal(14D, resources["BodyFontSize"]);
            Assert.Equal(12D, resources["CaptionFontSize"]);
            Assert.Equal("Segoe UI", ((FontFamily)resources["AppFontFamily"]).Source);

            Assert.IsType<Style>(resources["VoxFlowButtonStyle"]);
            Assert.IsType<Style>(resources["VoxFlowCardStyle"]);
            Assert.IsType<Style>(resources["VoxFlowToggleButtonStyle"]);
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Theme_manager_applies_and_persists_an_app_owned_mode()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var preferences = new CapturingThemePreferenceStore(AppThemeMode.Light);
            var firstResources = new ResourceDictionary();
            var firstManager = new ThemeManager(firstResources, preferences);

            firstManager.Initialize();
            Assert.Equal(AppThemeMode.Light, firstManager.CurrentMode);
            AssertBrush(firstResources, "PageBackgroundBrush", "#FFF6F9F7");

            firstManager.Apply(AppThemeMode.Dark);
            Assert.Equal(AppThemeMode.Dark, preferences.StoredMode);
            AssertBrush(firstResources, "PageBackgroundBrush", "#FF141816");

            var restoredResources = new ResourceDictionary();
            var restoredManager = new ThemeManager(restoredResources, preferences);
            restoredManager.Initialize();

            Assert.Equal(AppThemeMode.Dark, restoredManager.CurrentMode);
            AssertBrush(restoredResources, "PageBackgroundBrush", "#FF141816");
            return Task.CompletedTask;
        });
    }

    [Fact]
    public void File_preference_store_round_trips_the_app_owned_theme()
    {
        using var directory = new TemporaryDirectory();
        var preferencePath = Path.Combine(directory.Path, "ui", "theme.txt");
        var store = new FileThemePreferenceStore(preferencePath);

        Assert.Equal(AppThemeMode.Light, store.Load());

        store.Save(AppThemeMode.Dark);

        Assert.Equal(AppThemeMode.Dark, new FileThemePreferenceStore(preferencePath).Load());
        Assert.Equal("Dark", File.ReadAllText(preferencePath));
        Assert.False(File.Exists(preferencePath + ".tmp"));
    }

    [Fact]
    public void File_preference_store_falls_back_to_light_for_invalid_content()
    {
        using var directory = new TemporaryDirectory();
        var preferencePath = Path.Combine(directory.Path, "theme.txt");
        File.WriteAllText(preferencePath, "system");

        Assert.Equal(
            AppThemeMode.Light,
            new FileThemePreferenceStore(preferencePath).Load());
    }

    private static void AssertColor(
        ResourceDictionary resources,
        string key,
        string expected) =>
        Assert.Equal(
            (Color)ColorConverter.ConvertFromString(expected),
            Assert.IsType<Color>(resources[key]));

    private static void AssertBrush(
        ResourceDictionary resources,
        string key,
        string expected) =>
        Assert.Equal(
            (Color)ColorConverter.ConvertFromString(expected),
            Assert.IsType<SolidColorBrush>(resources[key]).Color);

    private sealed class CapturingThemePreferenceStore(AppThemeMode initialMode)
        : IThemePreferenceStore
    {
        public AppThemeMode StoredMode { get; private set; } = initialMode;

        public AppThemeMode Load() => StoredMode;

        public void Save(AppThemeMode mode) => StoredMode = mode;
    }
}
