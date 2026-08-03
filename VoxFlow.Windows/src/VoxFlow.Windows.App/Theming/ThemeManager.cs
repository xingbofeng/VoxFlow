using System.Windows;

namespace VoxFlow.Windows.App.Theming;

public sealed class ThemeManager(
    ResourceDictionary applicationResources,
    IThemePreferenceStore preferenceStore)
{
    private ResourceDictionary? appliedResources;

    public AppThemeMode CurrentMode { get; private set; }

    public void Initialize() => ApplyCore(preferenceStore.Load(), persist: false);

    public void Apply(AppThemeMode mode) => ApplyCore(mode, persist: true);

    private void ApplyCore(AppThemeMode mode, bool persist)
    {
        var replacement = ThemeResourceLoader.Load(mode);
        if (appliedResources is not null)
        {
            applicationResources.MergedDictionaries.Remove(appliedResources);
        }

        applicationResources.MergedDictionaries.Add(replacement);
        appliedResources = replacement;
        CurrentMode = mode;

        if (persist)
        {
            preferenceStore.Save(mode);
        }
    }
}
