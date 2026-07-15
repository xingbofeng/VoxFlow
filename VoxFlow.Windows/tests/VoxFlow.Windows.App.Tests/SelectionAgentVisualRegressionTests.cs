using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.App.Settings;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Application.SelectionTransform;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class SelectionAgentVisualRegressionTests
{
    private const double MaximumMeanCellDifference = 8;
    private static readonly double[] DpiScales = [1, 1.25, 1.5, 2];
    private static readonly string[] SurfaceNames =
    [
        "llm-settings",
        "agent-settings",
        "selection-result",
        "agent-hud",
        "agent-question",
        "agent-history-detail",
    ];

    [Fact]
    public async Task Selection_and_agent_surfaces_match_light_dark_and_four_dpi_baselines()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var originalCulture = CultureInfo.CurrentUICulture;
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("zh-Hans");
            try
            {
                var actual = new SortedDictionary<string, string>(StringComparer.Ordinal);
                foreach (var theme in Enum.GetValues<AppThemeMode>())
                {
                    ApplyApplicationTheme(theme);
                    foreach (var surfaceName in SurfaceNames)
                    {
                        foreach (var scale in DpiScales)
                        {
                            var key = $"{theme.ToString().ToLowerInvariant()}/{surfaceName}/{scale:0.##}";
                            var surface = await CreateSurfaceAsync(surfaceName);
                            actual[key] = Convert.ToBase64String(Render(theme, surface, scale, key));
                        }
                    }
                }

                var updatePath = Environment.GetEnvironmentVariable("VOXFLOW_UPDATE_SELECTION_AGENT_VISUAL_BASELINE_PATH");
                if (!string.IsNullOrWhiteSpace(updatePath))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(updatePath)
                        ?? throw new InvalidOperationException("Baseline path has no directory."));
                    File.WriteAllText(updatePath, JsonSerializer.Serialize(
                        actual,
                        new JsonSerializerOptions { WriteIndented = true }));
                }

                var expectedPath = Path.Combine(
                    AppContext.BaseDirectory,
                    "TestResources",
                    "VisualBaselines",
                    "selection-agent-signatures.json");
                Assert.True(File.Exists(expectedPath), "The approved selection/Agent visual baseline is missing.");
                var expected = JsonSerializer.Deserialize<SortedDictionary<string, string>>(
                    File.ReadAllText(expectedPath))
                    ?? throw new InvalidDataException("Selection/Agent visual baseline JSON is empty.");
                Assert.Equal(expected.Keys, actual.Keys);
                foreach (var key in expected.Keys)
                {
                    var difference = MeanDifference(
                        Convert.FromBase64String(expected[key]),
                        Convert.FromBase64String(actual[key]));
                    Assert.True(
                        difference <= MaximumMeanCellDifference,
                        $"Visual regression for {key}: mean cell difference {difference:0.00}.");
                }
            }
            finally
            {
                CultureInfo.CurrentUICulture = originalCulture;
            }
        }, timeout: TimeSpan.FromMinutes(5));
    }

    private static void ApplyApplicationTheme(AppThemeMode theme)
    {
        var application = System.Windows.Application.Current
            ?? new System.Windows.Application
            {
                ShutdownMode = ShutdownMode.OnExplicitShutdown,
            };
        application.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        application.Resources.MergedDictionaries.Clear();
        application.Resources.MergedDictionaries.Add(ThemeResourceLoader.Load(theme));
    }

    private static async Task<VisualSurface> CreateSurfaceAsync(string name) => name switch
    {
        "llm-settings" => await CreateModelsSurfaceAsync(ModelsSettingsTab.Llm),
        "agent-settings" => await CreateModelsSurfaceAsync(ModelsSettingsTab.Agent),
        "selection-result" => await CreateSelectionResultSurfaceAsync(),
        "agent-hud" => CreateAgentHudSurface(),
        "agent-question" => CreateAgentQuestionSurface(),
        "agent-history-detail" => CreateAgentHistorySurface(),
        _ => throw new ArgumentOutOfRangeException(nameof(name), name, null),
    };

    private static async Task<VisualSurface> CreateModelsSurfaceAsync(ModelsSettingsTab selectedTab)
    {
        var provider = Provider();
        var service = new VisualProviderService(provider);
        var page = new ModelsSettingsPageViewModel(
            new OpenAiSettingsCardViewModel(new SettingsStateCoordinator(
                new VoxFlow.Windows.Application.State.VoxFlowStateStore())),
            llmProviderManagement: service,
            builtinAgentRuntime: new BuiltinAgentRuntimeStatus(
                BuiltinAgentRuntimeAvailability.Available,
                "0.1.0",
                new BuiltinAgentBinaryDescriptor(
                    @"C:\Program Files\VoxFlow\runtime\agent\voxflow-agent.exe",
                    "d3050e7c2bfbdc75ae71bf672891600c79f315386ebff1875a60725284f6a4cf"))
            {
                ExpectedSha256 = "d3050e7c2bfbdc75ae71bf672891600c79f315386ebff1875a60725284f6a4cf",
            });
        await page.LlmProviders!.LoadAsync(CancellationToken.None);
        // Editor is a modal sheet (mac parity), not an inline card. Keep the LLM
        // tab list surface stable for baseline comparison.
        page.SelectedTab = selectedTab;
        var view = new ModelsSettingsView { DataContext = page };
        return PageSurface(
            new ScrollViewer
            {
                Content = view,
                Padding = new Thickness(28),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            },
            1000,
            720);
    }

    private static async Task<VisualSurface> CreateSelectionResultSurfaceAsync()
    {
        var viewModel = new SelectionResultViewModel(
            "VoxFlow should keep code such as git push origin main unchanged while translating this selected paragraph.",
            SelectionTransformOperation.Translation,
            new VisualSelectionTransformService(),
            writer: new VisualSelectionWriter());
        await viewModel.StartAsync();
        var window = new SelectionResultWindow { DataContext = viewModel };
        return new VisualSurface((FrameworkElement)window.Content, 440, 560);
    }

    private static VisualSurface CreateAgentHudSurface()
    {
        var window = new HudWindow();
        window.DataContext = new HudWindowViewModel();
        ((HudWindowViewModel)window.DataContext).Update(
            AgentHudPresentationMapper.CompletedSummary("已完成：创建并更新项目报告，没有自动发送内容。"));
        return new VisualSurface((FrameworkElement)window.Content, 520, 72);
    }

    private static VisualSurface CreateAgentQuestionSurface()
    {
        var completion = new TaskCompletionSource<IReadOnlyDictionary<string, IReadOnlyList<string>>?>();
        var window = new AgentQuestionWindow(
        [
            new AgentQuestion(
                "请选择报告输出格式",
                "输出格式",
                [
                    new AgentQuestionOption("Markdown", "适合版本管理和继续编辑。", "report.md"),
                    new AgentQuestionOption("HTML", "适合直接在浏览器中查看。", "report.html"),
                ],
                MultiSelect: false),
            new AgentQuestion(
                "需要包含哪些部分",
                "报告内容",
                [
                    new AgentQuestionOption("摘要", "包含一段简洁结论。", null),
                    new AgentQuestionOption("行动项", "列出后续负责人和动作。", null),
                ],
                MultiSelect: true),
        ], completion);
        return new VisualSurface((FrameworkElement)window.Content, 540, 680);
    }

    private static VisualSurface CreateAgentHistorySurface()
    {
        var now = new DateTimeOffset(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);
        var trace = new AgentActionTrace(
            "openai",
            AgentExecutionMode.BuiltinAgent,
            WorkflowTaskStatus.Completed,
            "帮我把当前项目整理成一份报告",
            now.ToUnixTimeMilliseconds(),
            screenContext: new AgentScreenContextMetadata(
                "Visual Studio Code",
                "Code.exe",
                "README.md",
                ["selectedText", "uiaVisibleText"],
                ["ocrSkipped"],
                now.ToUnixTimeMilliseconds()),
            events:
            [
                new AgentActionEvent(
                    "event-1",
                    AgentActionEventKind.ToolResolved,
                    "文件已写入",
                    "report.md · 2.1 KB",
                    now.AddSeconds(1).ToUnixTimeMilliseconds(),
                    elapsedMs: 120,
                    toolName: "write_file",
                    isFailure: false),
            ],
            resultSummary: "报告已创建",
            model: "qwen3.5-plus",
            artifacts:
            [
                new AgentArtifact(
                    "artifact-1",
                    AgentArtifactKind.File,
                    @"~\report.md",
                    "项目报告",
                    now.AddSeconds(1).ToUnixTimeMilliseconds()),
            ],
            completedAtUnixMs: now.AddSeconds(2).ToUnixTimeMilliseconds());
        var task = new WorkflowTaskRecord(
            "agent-visual",
            WorkflowTaskKind.AgentCompose,
            WorkflowTaskStage.Completed,
            WorkflowTaskStatus.Completed,
            Guid.NewGuid(),
            "帮我把当前项目整理成一份报告",
            null,
            "报告已创建",
            "openai",
            "qwen3.5-plus",
            null,
            JsonSerializer.SerializeToElement(new { sources = new[] { "selectedText", "uiaVisibleText" } }),
            JsonSerializer.SerializeToElement(trace, DomainJson.Options),
            null,
            null,
            null,
            now.ToUnixTimeMilliseconds(),
            now.AddSeconds(2).ToUnixTimeMilliseconds(),
            now.AddSeconds(2).ToUnixTimeMilliseconds());
        var store = new VisualHistoryStore();
        var viewModel = new HomeDashboardViewModel(
            store,
            new VisualClipboardWriter(),
            new FixedTimeProvider(now),
            unifiedHistory: new UnifiedHistoryQueryService(
                store,
                new VisualWorkflowRepository(task)));
        viewModel.Reload();
        Assert.True(viewModel.OpenDetail("workflow:agent-visual"));
        return PageSurface(new HomeDashboardView { DataContext = viewModel }, 1000, 720);
    }

    private static VisualSurface PageSurface(FrameworkElement content, double width, double height)
    {
        var background = new Border { Child = content };
        background.SetResourceReference(Border.BackgroundProperty, "PageBackgroundBrush");
        background.SetResourceReference(TextElement.ForegroundProperty, "PrimaryTextBrush");
        background.SetResourceReference(TextElement.FontFamilyProperty, "AppFontFamily");
        return new VisualSurface(background, width, height);
    }

    private static byte[] Render(AppThemeMode theme, VisualSurface surface, double scale, string evidenceName)
    {
        var root = surface.Root;
        root.Resources.MergedDictionaries.Add(ThemeResourceLoader.Load(theme));
        root.Width = surface.Width;
        root.Height = surface.Height;
        root.Measure(new Size(surface.Width, surface.Height));
        root.Arrange(new Rect(0, 0, surface.Width, surface.Height));
        root.UpdateLayout();
        Assert.Equal(surface.Width, root.ActualWidth, precision: 2);
        Assert.Equal(surface.Height, root.ActualHeight, precision: 2);

        var bitmap = new RenderTargetBitmap(
            checked((int)Math.Round(surface.Width * scale)),
            checked((int)Math.Round(surface.Height * scale)),
            96 * scale,
            96 * scale,
            PixelFormats.Pbgra32);
        bitmap.Render(root);
        SaveEvidence(bitmap, evidenceName);
        return Signature(bitmap, columns: 16, rows: 10);
    }

    private static byte[] Signature(BitmapSource bitmap, int columns, int rows)
    {
        var stride = bitmap.PixelWidth * 4;
        var pixels = new byte[stride * bitmap.PixelHeight];
        bitmap.CopyPixels(pixels, stride, 0);
        var signature = new byte[columns * rows * 3];
        for (var row = 0; row < rows; row++)
        {
            var y0 = row * bitmap.PixelHeight / rows;
            var y1 = (row + 1) * bitmap.PixelHeight / rows;
            for (var column = 0; column < columns; column++)
            {
                var x0 = column * bitmap.PixelWidth / columns;
                var x1 = (column + 1) * bitmap.PixelWidth / columns;
                long red = 0, green = 0, blue = 0, count = 0;
                for (var y = y0; y < y1; y += Math.Max(1, (y1 - y0) / 8))
                {
                    for (var x = x0; x < x1; x += Math.Max(1, (x1 - x0) / 8))
                    {
                        var offset = y * stride + x * 4;
                        blue += pixels[offset];
                        green += pixels[offset + 1];
                        red += pixels[offset + 2];
                        count++;
                    }
                }
                var target = (row * columns + column) * 3;
                signature[target] = checked((byte)(red / count));
                signature[target + 1] = checked((byte)(green / count));
                signature[target + 2] = checked((byte)(blue / count));
            }
        }
        return signature;
    }

    private static void SaveEvidence(BitmapSource bitmap, string name)
    {
        var root = Environment.GetEnvironmentVariable("VOXFLOW_SELECTION_AGENT_VISUAL_EVIDENCE_ROOT");
        if (string.IsNullOrWhiteSpace(root)) return;
        Directory.CreateDirectory(root);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(Path.Combine(root, name.Replace('/', '-') + ".png"));
        encoder.Save(stream);
    }

    private static double MeanDifference(byte[] expected, byte[] actual)
    {
        Assert.Equal(expected.Length, actual.Length);
        return expected.Zip(actual, (left, right) => Math.Abs(left - right)).Average();
    }

    private static LlmProviderRecord Provider() => new(
        "openai",
        "OpenAI",
        LlmProviderType.OpenAiCompatible,
        new Uri("https://tokenhub.tencentmaas.com/v1"),
        "qwen3.5-plus",
        "llm-provider/openai/api_key",
        0.2,
        30,
        true,
        true,
        LlmProviderHealthStatus.Ok,
        "completion_ok",
        23,
        900,
        LlmAgentCapabilityStatus.Supported,
        "tool_calls_ok",
        901,
        100,
        901);

    private sealed record VisualSurface(FrameworkElement Root, double Width, double Height);

    private sealed class VisualSelectionTransformService : ISelectionTransformStreamingService
    {
        public async IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
            SelectionTransformRequest request,
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            yield return new SelectionTransformStarted(request.Generation);
            await Task.Yield();
            cancellationToken.ThrowIfCancellationRequested();
            yield return new SelectionTransformPartial(request.Generation, "VoxFlow 在翻译时应保留");
            yield return new SelectionTransformCompleted(
                request.Generation,
                "VoxFlow 在翻译这段选中文字时，应原样保留 git push origin main 等代码内容。");
        }
    }

    private sealed class VisualSelectionWriter : ISelectionResultWriter
    {
        public Task<bool> ReplaceAsync(string text, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> InsertAfterAsync(string text, CancellationToken cancellationToken) => Task.FromResult(true);
    }

    private sealed class VisualProviderService(params LlmProviderRecord[] providers) : ILlmProviderManagementService
    {
        private readonly List<LlmProviderRecord> values = [.. providers];
        public IReadOnlyList<LlmProviderRecord> List() => values.ToArray();
        public Task<LlmProviderRecord> SaveAsync(LlmProviderDraft draft, string? apiKey, bool retainExistingCredential, CancellationToken cancellationToken) => throw new NotSupportedException();
        public bool SetDefault(string providerId) => false;
        public bool SetEnabled(string providerId, bool enabled) => false;
        public Task<bool> DeleteAsync(string providerId, CancellationToken cancellationToken) => Task.FromResult(false);
        public ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(string providerId, CancellationToken cancellationToken) => ValueTask.FromResult(new LlmModelDiscoveryResult([], LlmModelDiscoverySource.ManualOnly));
        public ValueTask<LlmConnectionTestResult> TestConnectionAsync(string providerId, CancellationToken cancellationToken) => ValueTask.FromResult(new LlmConnectionTestResult(LlmConnectionTestStatus.Succeeded, 23, null));
        public ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(string providerId, CancellationToken cancellationToken) => ValueTask.FromResult(new LlmAgentCapabilityTestResult(LlmAgentCapabilityStatus.Supported, "tool_calls_ok"));
        public Task<CredentialPresentation> GetCredentialPresentationAsync(string providerId, CancellationToken cancellationToken) => Task.FromResult(new CredentialPresentation(CredentialAvailability.Available, "••••••••"));
        public Task<string?> RevealApiKeyAsync(string providerId, CancellationToken cancellationToken) => Task.FromResult<string?>(null);
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class VisualClipboardWriter : ITextClipboardWriter
    {
        public void WriteText(string text) { }
    }

    private sealed class VisualHistoryStore : IHistoryStore
    {
        public HistoryMaintenanceResult WriteAndPrune(HistoryEntry entry, DateTimeOffset? deleteBeforeUtcExclusive) => new(false, 0);
        public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) => 0;
        public IReadOnlyList<HistoryEntry> ReadAll() => [];
        public int Delete(IReadOnlyCollection<string> ids) => 0;
        public int Clear() => 0;
        public bool UpdateFinalText(string id, string finalText) => false;
    }

    private sealed class VisualWorkflowRepository(params WorkflowTaskRecord[] tasks) : IWorkflowTaskRepository
    {
        private readonly List<WorkflowTaskRecord> values = [.. tasks];
        public void Create(WorkflowTaskRecord task) => throw new NotSupportedException();
        public WorkflowTaskRecord? Get(string id) => values.FirstOrDefault(task => task.Id == id);
        public WorkflowTaskPage Search(WorkflowTaskQuery query) => new(values.Skip(query.Offset).Take(query.Limit).ToArray(), values.Count, query.Offset, query.Limit);
        public bool TryUpdate(WorkflowTaskRecord task, Guid expectedGeneration) => false;
        public bool Delete(string id) => false;
        public IReadOnlyList<string> ListActiveIds() => [];
        public int PruneTerminalBefore(long cutoffUnixMs) => 0;
        public int MarkActiveAsInterrupted(long interruptedAtUnixMs) => 0;
    }
}
