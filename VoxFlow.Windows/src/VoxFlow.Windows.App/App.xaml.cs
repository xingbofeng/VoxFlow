using System.IO;
using System.Diagnostics;
using System.Windows;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App;

public partial class App : System.Windows.Application
{
    private ThemeManager? themeManager;
    private WindowsAppCompositionRoot? composition;
    private SharedAppStateProjection? sharedState;
    private SettingsStateCoordinator? settingsCoordinator;
    private SettingsPageViewModel? settingsPage;
    private WindowsTrayIcon? trayIcon;
    private bool isExiting;

    protected override void OnStartup(StartupEventArgs e)
    {
        var preferencePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow",
            "ui",
            "theme.txt");
        themeManager = new ThemeManager(
            Resources,
            new FileThemePreferenceStore(preferencePath));
        themeManager.Initialize();

        base.OnStartup(e);

        var dataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow");
        composition = new WindowsAppCompositionRoot(
            Path.Combine(dataRoot, "voxflow.db"));
        sharedState = new SharedAppStateProjection(composition.StateStore);
        settingsCoordinator = new SettingsStateCoordinator(composition.StateStore);
        settingsPage = new SettingsPageViewModel(
            L10n.Localize("SettingsHeading"),
            L10n.Localize("SettingsSubtitle"),
            composition.StateStore,
            composition.TextSettingsStore,
            composition.OpenAiSettingsService,
            composition.CloudAsrSettings);
        settingsPage.InitializeAsync(CancellationToken.None).GetAwaiter().GetResult();

        var home = new HomeDashboardViewModel(
            composition.HistoryStore,
            new WpfTextClipboardWriter(),
            TimeProvider.System);
        home.Reload();
        var window = new MainWindow(
            home,
            settingsPage,
            composition.CreateFileTranscriptionPageViewModel());
        MainWindow = window;
        window.Closing += OnMainWindowClosing;
        trayIcon = new WindowsTrayIcon(sharedState, ExecuteTrayCommand);
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        trayIcon?.Dispose();
        trayIcon = null;
        sharedState?.Dispose();
        sharedState = null;
        composition?.Dispose();
        composition = null;
        base.OnExit(e);
    }

    private void ExecuteTrayCommand(string commandId)
    {
        if (TryApplyTrayOption(commandId))
        {
            return;
        }

        switch (commandId)
        {
            case "app.openWindow":
                ShowMainWindow(openSettings: false);
                break;
            case "app.openSettings":
                ShowMainWindow(openSettings: true);
                break;
            case "app.openGithub":
                OpenShellTarget("https://github.com/xingbofeng/VoxFlow");
                break;
            case "app.openPermissions":
                OpenShellTarget("ms-settings:privacy-microphone");
                break;
            case "app.exit":
                isExiting = true;
                foreach (Window window in Windows)
                {
                    window.Close();
                }

                Shutdown();
                break;
        }
    }

    private void ShowMainWindow(bool openSettings)
    {
        var window = Windows.OfType<MainWindow>().FirstOrDefault();
        if (window is null)
        {
            window = new MainWindow(
                homeDashboard: null,
                settingsPage,
                composition?.CreateFileTranscriptionPageViewModel());
            MainWindow = window;
            window.Closing += OnMainWindowClosing;
        }

        if (openSettings)
        {
            window.ViewModel.TryNavigate("settings");
        }

        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        window.Show();
        window.Activate();
    }

    private void OnMainWindowClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (isExiting || sender is not MainWindow window)
        {
            return;
        }

        e.Cancel = true;
        window.Hide();
    }

    private static void OpenShellTarget(string target)
    {
        _ = Process.Start(new ProcessStartInfo(target)
        {
            UseShellExecute = true,
        });
    }

    private bool TryApplyTrayOption(string commandId)
    {
        if (composition is null || settingsCoordinator is null || sharedState is null)
        {
            return false;
        }

        var language = commandId switch
        {
            "language.auto" => RecognitionLanguage.Automatic,
            "language.zh-CN" => RecognitionLanguage.ChineseMandarin,
            "language.en-US" => RecognitionLanguage.English,
            "language.ja-JP" => RecognitionLanguage.Japanese,
            "language.ko-KR" => RecognitionLanguage.Korean,
            _ => (RecognitionLanguage?)null,
        };
        if (language is not null)
        {
            composition.StateStore.Dispatch(new UpdateSettingsCommand(
                new Dictionary<string, string?>
                {
                    ["recognition.language"] = language.Value.ToString(),
                },
                StateChangeKind.Settings | StateChangeKind.Dictation));
            return true;
        }

        if (commandId == "openai.enabled")
        {
            var state = sharedState.Current.TrayMenu;
            if (!state.OpenAiConfigured)
            {
                return true;
            }

            settingsCoordinator.RecordOpenAi(
                configured: true,
                enabled: !state.OpenAiEnabled);
            return true;
        }

        var selection = commandId switch
        {
            "asr.qwen.0.6b" => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B),
            "asr.qwen.1.7b" => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen17B),
            "asr.tencent" => new AsrSelection(AsrProviderId.TencentCloud, null),
            "asr.aliyun" => new AsrSelection(AsrProviderId.AliyunDashScope, null),
            "asr.volcengine" => new AsrSelection(AsrProviderId.Volcengine, null),
            _ => null,
        };
        if (selection is null)
        {
            return false;
        }

        try
        {
            settingsCoordinator.SelectAsr(
                selection.Provider,
                selection.QwenVariant);
        }
        catch (InvalidOperationException)
        {
            // Disabled tray items cannot normally execute; retain the current
            // provider if a stale native menu event arrives during a refresh.
        }

        return true;
    }
}
