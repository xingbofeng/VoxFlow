using Microsoft.Win32;

namespace VoxFlow.Windows.App.Settings;

public sealed class WindowsLaunchAtLoginService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "VoxFlow";
    private readonly Func<string?> executablePath;

    public WindowsLaunchAtLoginService(Func<string?>? executablePath = null)
    {
        this.executablePath = executablePath ?? (() => Environment.ProcessPath);
    }

    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(ValueName) is string value
            && !string.IsNullOrWhiteSpace(value);
    }

    public void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true)
            ?? throw new InvalidOperationException("The Windows startup registry key is unavailable.");
        if (!enabled)
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
            return;
        }

        var path = executablePath();
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new InvalidOperationException("The VoxFlow executable path is unavailable.");
        }
        key.SetValue(ValueName, $"\"{System.IO.Path.GetFullPath(path)}\"");
    }
}
