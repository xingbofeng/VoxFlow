using System.Windows;
using VoxFlow.Windows.App.Theming.Resources;

namespace VoxFlow.Windows.App.Theming;

public static class ThemeResourceLoader
{
    public static ResourceDictionary Load(AppThemeMode mode)
    {
        var resources = new ResourceDictionary();
        resources.MergedDictionaries.Add(new SharedThemeResources());
        resources.MergedDictionaries.Add(mode switch
        {
            AppThemeMode.Light => new LightThemeResources(),
            AppThemeMode.Dark => new DarkThemeResources(),
            _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, null),
        });
        return resources;
    }
}
