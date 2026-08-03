namespace VoxFlow.Windows.App.Theming;

public interface IThemePreferenceStore
{
    AppThemeMode Load();

    void Save(AppThemeMode mode);
}
