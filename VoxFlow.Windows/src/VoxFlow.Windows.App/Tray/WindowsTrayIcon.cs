using System.Drawing;
using System.Runtime.InteropServices;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tray;

public sealed class MutableTrayMenuStateSource : ITrayMenuStateSource
{
    private readonly object syncRoot = new();
    private TrayMenuState state;

    public MutableTrayMenuStateSource(TrayMenuState? initial = null)
    {
        state = initial ?? new TrayMenuState(
            RecognitionLanguage.Automatic,
            SelectedAsr: null,
            AsrChoices:
            [
                new(AsrProviderId.Qwen, QwenVariant.Qwen06B, false, false),
                new(AsrProviderId.Qwen, QwenVariant.Qwen17B, false, false),
                new(AsrProviderId.TencentCloud, null, false, false),
                new(AsrProviderId.AliyunDashScope, null, false, false),
                new(AsrProviderId.Volcengine, null, false, false),
            ],
            OpenAiConfigured: false,
            OpenAiEnabled: false,
            Agent: new TrayAgentState(
                RuntimeAvailable: false,
                ProviderConfigured: false,
                ConnectionHealthy: false,
                ToolCallingSupported: false,
                DictationPhase.Idle));
    }

    public TrayMenuState Read()
    {
        lock (syncRoot)
        {
            return state;
        }
    }

    public bool TryApplyOption(string id)
    {
        lock (syncRoot)
        {
            if (TryLanguage(id, out var language))
            {
                state = state with { Language = language };
                return true;
            }

            if (id == "openai.enabled" && state.OpenAiConfigured)
            {
                state = state with { OpenAiEnabled = !state.OpenAiEnabled };
                return true;
            }

            if (!TryAsr(id, out var provider, out var variant))
            {
                return false;
            }

            var availability = state.AsrChoices.FirstOrDefault(choice =>
                choice.Provider == provider && choice.QwenVariant == variant);
            if (availability is not { IsConfigured: true, IsReady: true })
            {
                return false;
            }

            state = state with { SelectedAsr = new AsrSelection(provider, variant) };
            return true;
        }
    }

    private static bool TryLanguage(string id, out RecognitionLanguage language)
    {
        language = id switch
        {
            "language.auto" => RecognitionLanguage.Automatic,
            "language.zh-CN" => RecognitionLanguage.ChineseMandarin,
            "language.en-US" => RecognitionLanguage.English,
            "language.ja-JP" => RecognitionLanguage.Japanese,
            "language.ko-KR" => RecognitionLanguage.Korean,
            _ => default,
        };
        return id.StartsWith("language.", StringComparison.Ordinal)
            && id is "language.auto" or "language.zh-CN" or "language.en-US"
                or "language.ja-JP" or "language.ko-KR";
    }

    private static bool TryAsr(
        string id,
        out AsrProviderId provider,
        out QwenVariant? variant)
    {
        (provider, variant) = id switch
        {
            "asr.qwen.0.6b" => (AsrProviderId.Qwen, QwenVariant.Qwen06B),
            "asr.qwen.1.7b" => (AsrProviderId.Qwen, QwenVariant.Qwen17B),
            "asr.tencent" => (AsrProviderId.TencentCloud, (QwenVariant?)null),
            "asr.aliyun" => (AsrProviderId.AliyunDashScope, (QwenVariant?)null),
            "asr.volcengine" => (AsrProviderId.Volcengine, (QwenVariant?)null),
            _ => (default, (QwenVariant?)null),
        };
        return id.StartsWith("asr.", StringComparison.Ordinal)
            && id is "asr.qwen.0.6b" or "asr.qwen.1.7b" or "asr.tencent"
                or "asr.aliyun" or "asr.volcengine";
    }
}

public sealed class WindowsTrayIcon : ITrayMenuView, IDisposable
{
    private const string TrayIconResourceName = "VoxFlow.Windows.App.Assets.VoxFlow.png";
    private readonly System.Windows.Forms.NotifyIcon notifyIcon;
    private Icon trayIcon;
    private readonly System.Windows.Forms.ContextMenuStrip contextMenu = new();
    private readonly TrayMenuController controller;
    private readonly Action<string> execute;
    private readonly Action? refreshState;
    private bool disposed;

    public WindowsTrayIcon(
        ITrayMenuStateSource stateSource,
        Action<string> execute,
        Action? refreshState = null)
    {
        ArgumentNullException.ThrowIfNull(stateSource);
        this.execute = execute ?? throw new ArgumentNullException(nameof(execute));
        this.refreshState = refreshState;
        controller = new TrayMenuController(stateSource, this);

        contextMenu.ShowImageMargin = false;
        contextMenu.Opening += (_, _) =>
        {
            refreshState?.Invoke();
            controller.OnMenuOpening();
        };
        trayIcon = LoadTrayIcon();
        notifyIcon = new System.Windows.Forms.NotifyIcon
        {
            ContextMenuStrip = contextMenu,
            Icon = trayIcon,
            Text = L10n.BrandName,
            Visible = true,
        };
        notifyIcon.DoubleClick += (_, _) => execute("app.openWindow");
    }

    public void ApplyGrayMode(bool enabled)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        var replacement = LoadTrayIcon(enabled);
        var previous = trayIcon;
        trayIcon = replacement;
        notifyIcon.Icon = replacement;
        previous.Dispose();
    }

    public void Render(TrayMenuModel menu)
    {
        ArgumentNullException.ThrowIfNull(menu);
        contextMenu.SuspendLayout();
        try
        {
            contextMenu.Items.Clear();
            foreach (var item in menu.Items)
            {
                contextMenu.Items.Add(CreateItem(item));
            }
        }
        finally
        {
            contextMenu.ResumeLayout(performLayout: true);
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        trayIcon.Dispose();
        contextMenu.Dispose();
    }

    internal static Icon LoadTrayIcon(bool gray = false)
    {
        using var stream = typeof(WindowsTrayIcon).Assembly
            .GetManifestResourceStream(TrayIconResourceName)
            ?? throw new InvalidOperationException(
                $"Embedded tray icon '{TrayIconResourceName}' is missing.");
        using var bitmap = new Bitmap(stream);
        using var rendered = gray ? CreateGrayBitmap(bitmap) : new Bitmap(bitmap);
        var handle = rendered.GetHicon();
        try
        {
            using var source = Icon.FromHandle(handle);
            return (Icon)source.Clone();
        }
        finally
        {
            _ = DestroyIcon(handle);
        }
    }

    private static Bitmap CreateGrayBitmap(Bitmap source)
    {
        var result = new Bitmap(source.Width, source.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        for (var y = 0; y < source.Height; y++)
        {
            for (var x = 0; x < source.Width; x++)
            {
                var color = source.GetPixel(x, y);
                var luminance = (int)Math.Round(
                    (0.2126 * color.R) + (0.7152 * color.G) + (0.0722 * color.B));
                result.SetPixel(x, y, Color.FromArgb(color.A, luminance, luminance, luminance));
            }
        }
        return result;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint iconHandle);

    private System.Windows.Forms.ToolStripItem CreateItem(TrayMenuItemModel item)
    {
        if (item.Kind == TrayMenuItemKind.Separator)
        {
            return new System.Windows.Forms.ToolStripSeparator { Name = item.Id };
        }

        var menuItem = new System.Windows.Forms.ToolStripMenuItem
        {
            Name = item.Id,
            Text = TrayMenuLabels.For(item.Id),
            Enabled = item.IsEnabled,
            Checked = item.IsChecked,
            CheckOnClick = false,
        };
        if (item.Children is { Count: > 0 })
        {
            foreach (var child in item.Children)
            {
                menuItem.DropDownItems.Add(CreateItem(child));
            }
        }
        else if (item.Kind is TrayMenuItemKind.Action or TrayMenuItemKind.Option)
        {
            menuItem.Click += (_, _) => execute(item.Id);
        }

        return menuItem;
    }
}

internal static class TrayMenuLabels
{
    public static string For(string id) => L10n.Localize(id switch
    {
        "language" => "TrayLanguage",
        "language.auto" => "TrayLanguageAutomatic",
        "language.zh-CN" => "TrayLanguageChinese",
        "language.en-US" => "TrayLanguageEnglish",
        "language.ja-JP" => "TrayLanguageJapanese",
        "language.ko-KR" => "TrayLanguageKorean",
        "asr" => "TrayAsr",
        "asr.qwen.0.6b" => "TrayAsrQwen06B",
        "asr.qwen.1.7b" => "TrayAsrQwen17B",
        "asr.tencent" => "HistorySourceTencent",
        "asr.aliyun" => "HistorySourceAliyun",
        "asr.volcengine" => "HistorySourceVolcengine",
        "openai" => "TrayOpenAi",
        "openai.enabled" => "TrayOpenAiEnabled",
        "agent" => "TrayAgent",
        "agent.status.ready" => "TrayAgentReady",
        "agent.status.running" => "TrayAgentRunning",
        "agent.status.runtimeUnavailable" => "TrayAgentRuntimeUnavailable",
        "agent.status.providerUnavailable" => "TrayAgentProviderUnavailable",
        "agent.start" => "TrayAgentStart",
        "agent.stop" => "TrayAgentStop",
        "screenshot.start" => "TrayScreenshot",
        "selection.translate" => "SelectionResultTranslation",
        "selection.summary" => "SelectionResultSummary",
        "app.openWindow" => "TrayOpenWindow",
        "app.openSettings" => "TrayOpenSettings",
        "app.openGithub" => "TrayOpenGithub",
        "app.openPermissions" => "TrayOpenPermissions",
        "app.exit" => "TrayExit",
        _ => throw new ArgumentOutOfRangeException(nameof(id), id, null),
    });
}
