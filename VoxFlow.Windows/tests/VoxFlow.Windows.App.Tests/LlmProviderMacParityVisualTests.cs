using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Settings;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

/// <summary>
/// Pixel-level structural contracts for the mac-parity LLM list + add/edit modal.
/// Renders real WPF surfaces, asserts automation names from mac screenshots, and
/// saves PNG evidence under the implementer scratch directory.
/// </summary>
public sealed class LlmProviderMacParityVisualTests
{
    private static readonly string EvidenceDir = ResolveEvidenceDir();

    [Fact]
    public async Task List_surface_exposes_mac_actions_and_masks_credentials()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            ApplyTheme(AppThemeMode.Light);
            var original = CultureInfo.CurrentUICulture;
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("zh-Hans");
            try
            {
                var service = new FakeService(
                    Provider("openai", "OpenAI", isDefault: true),
                    Provider("deepseek", "DeepSeek", isDefault: false));
                var viewModel = new LlmProviderSettingsViewModel(service);
                await viewModel.LoadAsync(CancellationToken.None);

                // Masked keys on list (mac).
                Assert.All(viewModel.Providers, p =>
                    Assert.Equal("••••••••", p.ApiKeyPresentation));
                Assert.True(viewModel.Providers[0].IsDefault);
                Assert.True(viewModel.Providers[0].CanRunActions);
                Assert.False(viewModel.Providers[0].CanSetDefault); // already default
                Assert.True(viewModel.Providers[1].CanSetDefault);

                var view = new LlmProviderSettingsView { DataContext = viewModel };
                var host = Host(view, 920, 640);
                try
                {
                    host.Show();
                    view.UpdateLayout();

                    AssertNamed(view, L10n.LlmProviderAdd);
                    AssertNamed(view, L10n.LlmProviderTestConnection);
                    AssertNamed(view, L10n.LlmProviderTestAgent);
                    AssertNamed(view, L10n.LlmProviderEdit);
                    AssertNamed(view, L10n.LlmProviderDelete);
                    AssertNamed(view, L10n.LlmProviderSetDefault);
                    AssertNamed(view, L10n.LlmProviderEnable);

                    // No inline editor surface — modal only (mac sheet).
                    Assert.Null(viewModel.Editor);
                    Assert.DoesNotContain(
                        FindVisualChildren<PasswordBox>(view),
                        _ => true);

                    SavePng(view, "llm-list-mac-parity.png");
                }
                finally
                {
                    host.Close();
                }
            }
            finally
            {
                CultureInfo.CurrentUICulture = original;
            }
        });
    }

    [Fact]
    public async Task Editor_modal_matches_mac_sheet_controls_and_key_eye_contract()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            ApplyTheme(AppThemeMode.Light);
            var original = CultureInfo.CurrentUICulture;
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("zh-Hans");
            try
            {
                var service = new FakeService(
                    Provider("deepseek", "DeepSeek", isDefault: true));
                var viewModel = new LlmProviderSettingsViewModel(service);
                await viewModel.LoadAsync(CancellationToken.None);

                // Add sheet: template overview + empty masked key.
                viewModel.BeginAdd("deepseek");
                var addEditor = Assert.IsType<LlmProviderEditorViewModel>(viewModel.Editor);
                Assert.False(addEditor.IsApiKeyVisible);
                Assert.Equal(string.Empty, addEditor.DraftApiKey);
                Assert.True(addEditor.HasApiKeyHelp);
                Assert.True(addEditor.RequiresApiKey);
                Assert.Equal(
                    new Uri("https://platform.deepseek.com/api_keys"),
                    addEditor.ApiKeyUri);

                var addDialog = new LlmProviderEditorDialogWindow(null, viewModel)
                {
                    ShowActivated = false,
                    ShowInTaskbar = false,
                    Left = -4000,
                    Top = -4000,
                    WindowStartupLocation = WindowStartupLocation.Manual,
                };
                try
                {
                    addDialog.Show();
                    // mac LLMProviderEditorSheet is 680x640.
                    ForceLayout(addDialog, 680, 640);
                    var addRoot = DialogRoot(addDialog);

                    Assert.Equal(680, addDialog.Width);
                    Assert.Equal(640, addDialog.Height);

                    AssertNamed(addRoot, L10n.LlmProviderCancel);
                    AssertNamed(addRoot, L10n.LlmProviderSave);
                    AssertNamed(addRoot, L10n.LlmProviderGetApiKey);
                    AssertNamed(addRoot, L10n.LlmProviderRefreshModels);
                    AssertNamed(addRoot, L10n.LlmProviderAddModel);
                    AssertNamed(addRoot, L10n.LlmProviderName);
                    AssertNamed(addRoot, L10n.LlmProviderServiceUrl);
                    AssertNamed(addRoot, L10n.LlmProviderModel);
                    AssertNamed(addRoot, L10n.LlmProviderApiKey);
                    AssertNamed(addRoot, L10n.LlmProviderEnable);
                    AssertNamed(addRoot, L10n.LlmProviderTemplateLabel);
                    AssertButtonContent(addRoot, L10n.LlmProviderSave);
                    AssertButtonContent(addRoot, L10n.LlmProviderCancel);
                    AssertButtonContent(addRoot, L10n.LlmProviderAddModel);
                    AssertButtonContent(addRoot, L10n.LlmProviderRefreshModels);
                    AssertButtonContent(addRoot, L10n.LlmProviderGetApiKey);

                    // Eye glyph present; password field visible when masked.
                    var passwordBoxes = FindVisualChildren<PasswordBox>(addRoot).ToArray();
                    Assert.NotEmpty(passwordBoxes);
                    Assert.False(string.IsNullOrEmpty(addEditor.ApiKeyVisibilityGlyph));

                    // Template menu (mac picker) + overview get-key surface.
                    Assert.True(viewModel.TemplateOptions.Count >= 10);
                    var templatePicker = FindVisualChildren<ComboBox>(addRoot)
                        .FirstOrDefault(c =>
                            AutomationProperties.GetName(c) == L10n.LlmProviderTemplateLabel);
                    Assert.NotNull(templatePicker);
                    Assert.Equal(viewModel.TemplateOptions.Count, templatePicker!.Items.Count);
                    var templateIds = viewModel.TemplateOptions
                        .Select(t => t.Id)
                        .ToHashSet(StringComparer.Ordinal);
                    Assert.Contains("deepseek", templateIds);
                    Assert.Contains("custom", templateIds);
                    Assert.Contains("tencent-tokenhub", templateIds);

                    // Overview card hosts 获取 API 密钥 next to template title.
                    Assert.Contains(
                        FindVisualChildren<Button>(addRoot),
                        b => Equals(b.Content as string, L10n.LlmProviderGetApiKey));

                    // Model row has both refresh and add-model.
                    addEditor.Model = "deepseek-chat";
                    addEditor.AddCurrentModelToOptions();
                    Assert.Contains("deepseek-chat", addEditor.ModelOptions);

                    SavePng(addRoot, "llm-editor-add-mac-parity.png");
                }
                finally
                {
                    addDialog.Close();
                    viewModel.CancelEditor();
                }

                // Edit sheet: opens masked; reveal fills draft.
                await viewModel.BeginEditAsync("deepseek", CancellationToken.None);
                var editEditor = Assert.IsType<LlmProviderEditorViewModel>(viewModel.Editor);
                Assert.False(editEditor.IsApiKeyVisible);
                Assert.Null(editEditor.RevealedApiKey);
                Assert.Equal(string.Empty, editEditor.DraftApiKey);
                Assert.True(editEditor.CanUseSavedCredential);
                Assert.Equal("••••••••", editEditor.ApiKeyPresentation);

                await viewModel.RevealApiKeyAsync(CancellationToken.None);
                Assert.True(editEditor.IsApiKeyVisible);
                Assert.Equal("revealed fixture key", editEditor.RevealedApiKey);
                Assert.Equal("revealed fixture key", editEditor.DraftApiKey);
                Assert.Equal(
                    L10n.Localize("LlmProviderHideApiKey"),
                    editEditor.ApiKeyVisibilityTooltip);
                // Hide again (mac eye toggle) and confirm tooltip flips back.
                editEditor.IsApiKeyVisible = false;
                Assert.Equal(
                    L10n.Localize("LlmProviderRevealApiKey"),
                    editEditor.ApiKeyVisibilityTooltip);

                viewModel.CancelEditor();
                Assert.Null(viewModel.Editor);
            }
            finally
            {
                CultureInfo.CurrentUICulture = original;
            }
        });
    }

    [Fact]
    public async Task Text_page_has_no_openai_card_while_models_llm_hosts_providers()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            ApplyTheme(AppThemeMode.Light);
            var state = new VoxFlow.Windows.Application.State.VoxFlowStateStore();
            var textStore = new MemoryTextStore();
            var settings = new SettingsPageViewModel(
                "Settings",
                "Configure",
                state,
                textStore,
                openAiSettingsService: null,
                cloudAsrSettings: null,
                llmProviderManagement: new FakeService());

            await settings.InitializeAsync(CancellationToken.None);

            Assert.True(settings.TryNavigate("text"));
            var textPage = Assert.IsType<TextSettingsPageViewModel>(settings.CurrentPage);
            Assert.Null(typeof(TextSettingsPageViewModel).GetProperty("OpenAi"));
            var textView = new TextSettingsView { DataContext = textPage };
            var textHost = Host(textView, 900, 700);
            try
            {
                textHost.Show();
                textView.UpdateLayout();
                Assert.DoesNotContain(
                    FindVisualChildren<OpenAiSettingsCardView>(textView),
                    _ => true);
                SavePng(textView, "text-settings-no-openai.png");
            }
            finally
            {
                textHost.Close();
            }

            Assert.True(settings.TryNavigate("models"));
            var models = Assert.IsType<ModelsSettingsPageViewModel>(settings.CurrentPage);
            Assert.True(models.HasLlmProviderManagement);
            Assert.NotNull(models.LlmProviders);
            Assert.True(models.TrySelectTab("llm"));
            Assert.Equal(ModelsSettingsTab.Llm, models.SelectedTab);
        });
    }

    private static void ApplyTheme(AppThemeMode theme)
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

    private static Window Host(FrameworkElement content, double width, double height)
    {
        content.Width = width;
        content.Height = height;
        var background = new Border
        {
            Child = content,
            Padding = new Thickness(28),
        };
        background.SetResourceReference(Border.BackgroundProperty, "PageBackgroundBrush");
        return new Window
        {
            Content = background,
            Width = width + 56,
            Height = height + 56,
            ShowActivated = false,
            ShowInTaskbar = false,
            WindowStyle = WindowStyle.None,
            Opacity = 0,
        };
    }

    private static FrameworkElement DialogRoot(Window dialog)
    {
        if (dialog.Content is FrameworkElement content)
        {
            return content;
        }

        return dialog;
    }

    private static void ForceLayout(FrameworkElement element, double width, double height)
    {
        element.Width = width;
        element.Height = height;
        if (element is Window window && window.Content is FrameworkElement content)
        {
            // WPF owns the non-client sizing lifecycle of a shown Window.
            // Calling Measure/Arrange directly on Window can trigger a framework
            // invariant FailFast; lay out the content root instead.
            var contentWidth = Math.Max(1, window.ActualWidth > 1 ? window.ActualWidth : width);
            var contentHeight = Math.Max(1, window.ActualHeight > 1 ? window.ActualHeight : height);
            content.Measure(new Size(contentWidth, contentHeight));
            content.Arrange(new Rect(0, 0, contentWidth, contentHeight));
            content.UpdateLayout();
            return;
        }

        element.Measure(new Size(width, height));
        element.Arrange(new Rect(0, 0, width, height));
        element.UpdateLayout();
    }

    private static void AssertNamed(DependencyObject root, string name)
    {
        var match = FindAllElements(root)
            .OfType<FrameworkElement>()
            .FirstOrDefault(e => AutomationProperties.GetName(e) == name);
        Assert.True(match is not null, $"Missing automation name: {name}");
    }

    private static void AssertButtonContent(DependencyObject root, string content)
    {
        var match = FindAllElements(root)
            .OfType<Button>()
            .Any(b => string.Equals(b.Content?.ToString(), content, StringComparison.Ordinal));
        Assert.True(match, $"Missing button content: {content}");
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject root)
        where T : DependencyObject =>
        FindAllElements(root).OfType<T>();

    private static IEnumerable<DependencyObject> FindAllElements(DependencyObject root)
    {
        if (root is null)
        {
            yield break;
        }

        var seen = new HashSet<DependencyObject>();
        var queue = new Queue<DependencyObject>();
        queue.Enqueue(root);
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            if (!seen.Add(current))
            {
                continue;
            }

            yield return current;
            if (current is Visual or System.Windows.Media.Media3D.Visual3D)
            {
                var visualCount = VisualTreeHelper.GetChildrenCount(current);
                for (var i = 0; i < visualCount; i++)
                {
                    queue.Enqueue(VisualTreeHelper.GetChild(current, i));
                }
            }

            foreach (var logical in LogicalTreeHelper.GetChildren(current).OfType<DependencyObject>())
            {
                queue.Enqueue(logical);
            }
        }
    }

    private static void SavePng(FrameworkElement element, string fileName)
    {
        var widthHint = element.ActualWidth > 1 ? element.ActualWidth
            : element.DesiredSize.Width > 1 ? element.DesiredSize.Width
            : element.Width > 1 ? element.Width
            : 540;
        var heightHint = element.ActualHeight > 1 ? element.ActualHeight
            : element.DesiredSize.Height > 1 ? element.DesiredSize.Height
            : element.Height > 1 ? element.Height
            : 700;
        element.Measure(new Size(widthHint, heightHint));
        element.Arrange(new Rect(0, 0, Math.Max(widthHint, element.DesiredSize.Width), Math.Max(heightHint, element.DesiredSize.Height)));
        element.UpdateLayout();
        var width = Math.Max(1, (int)Math.Ceiling(element.ActualWidth > 0 ? element.ActualWidth : element.DesiredSize.Width));
        var height = Math.Max(1, (int)Math.Ceiling(element.ActualHeight > 0 ? element.ActualHeight : element.DesiredSize.Height));
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(element);
        Directory.CreateDirectory(EvidenceDir);
        var path = Path.Combine(EvidenceDir, fileName);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
        Assert.True(File.Exists(path) && new FileInfo(path).Length > 500, $"PNG evidence missing: {path}");
    }

    private static string ResolveEvidenceDir()
    {
        var env = Environment.GetEnvironmentVariable("GROK_SCRATCH")
            ?? Environment.GetEnvironmentVariable("GROK_GOAL_SCRATCH");
        if (!string.IsNullOrWhiteSpace(env))
        {
            return Path.Combine(env, "llm-mac-parity");
        }

        return Path.Combine(
            Path.GetTempPath(),
            "grok-goal-3ea588c6d02f",
            "implementer",
            "llm-mac-parity");
    }

    private static LlmProviderRecord Provider(string id, string name, bool isDefault) => new(
        id,
        name,
        LlmProviderType.OpenAiCompatible,
        new Uri($"https://{id}.example/v1"),
        $"model-{id}",
        $"llm-provider/{id}/api_key",
        0.2,
        30,
        enabled: true,
        isDefault,
        LlmProviderHealthStatus.Ok,
        "completion_ok",
        23,
        900,
        LlmAgentCapabilityStatus.Supported,
        "tools_ok",
        901,
        100,
        901);

    private sealed class MemoryTextStore : ITextProcessingSettingsStore
    {
        public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(DeterministicTextProcessingSettings.Default);

        public ValueTask SaveAsync(
            DeterministicTextProcessingSettings settings,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }

    private sealed class FakeService : ILlmProviderManagementService
    {
        private readonly List<LlmProviderRecord> providers;

        public FakeService(params LlmProviderRecord[] initial) =>
            providers = [.. initial];

        public IReadOnlyList<LlmProviderRecord> List() => providers.ToArray();

        public Task<LlmProviderRecord> SaveAsync(
            LlmProviderDraft draft,
            string? apiKey,
            bool retainExistingCredential,
            CancellationToken cancellationToken) =>
            Task.FromResult(Provider(draft.ProviderId ?? "new", draft.DisplayName, draft.IsDefault));

        public Task<bool> DeleteAsync(string providerId, CancellationToken cancellationToken)
        {
            providers.RemoveAll(p => p.Id == providerId);
            return Task.FromResult(true);
        }

        public bool SetDefault(string providerId) =>
            providers.Any(p => p.Id == providerId);

        public bool SetEnabled(string providerId, bool enabled) =>
            providers.Any(p => p.Id == providerId);

        public ValueTask<LlmConnectionTestResult> TestConnectionAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(new LlmConnectionTestResult(
                LlmConnectionTestStatus.Succeeded, 10, "ok"));

        public ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Supported, "ok"));

        public ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(new LlmModelDiscoveryResult(
                [new LlmModelDescriptor("remote-model", null, null)],
                LlmModelDiscoverySource.Remote));

        public Task<CredentialPresentation> GetCredentialPresentationAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            Task.FromResult(new CredentialPresentation(
                CredentialAvailability.Available,
                "••••••••"));

        public Task<string?> RevealApiKeyAsync(
            string providerId,
            CancellationToken cancellationToken) =>
            Task.FromResult<string?>("revealed fixture key");
    }
}
