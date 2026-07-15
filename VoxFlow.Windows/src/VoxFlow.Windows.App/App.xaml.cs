using System.IO;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Threading;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Diagnostics;
using VoxFlow.Windows.App.Dialogs;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.SelectionTransform;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Audio;
using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.App.Settings;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Platform.Selection;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.App;

public partial class App : System.Windows.Application
{
    private readonly StartupDiagnosticLog startupDiagnostics;
    private ThemeManager? themeManager;
    private WindowsAppCompositionRoot? composition;
    private SharedAppStateProjection? sharedState;
    private SettingsStateCoordinator? settingsCoordinator;
    private SettingsPageViewModel? settingsPage;
    private WindowsTrayIcon? trayIcon;
    private WindowsDictationDesktopRuntime? dictationRuntime;
    private HudWindow? hudWindow;
    private SelectionTransformWindowController? selectionTransforms;
    private HomeDashboardViewModel? homeDashboard;
    private ScreenshotMediaPageViewModel? screenshotMediaPage;
    private WindowsScreenshotController? screenshotController;
    private ClipboardImageOcrService? clipboardImageOcr;
    private ClipboardImageWatcher? clipboardImageWatcher;
    private readonly ScreenshotKeyboardHookRouter screenshotKeyboardRouter = new();
    private CancellationTokenSource? screenshotReprocessCancellation;
    private bool clipboardImageOcrEnabled = true;
    private GeneralPreferenceStore? generalPreferenceStore;
    private GeneralPreferenceDocument generalPreferences = GeneralPreferenceDocument.Default;
    private WindowsSingleInstanceCoordinator? singleInstance;
    private bool secondaryActivationPending;
#if DEBUG
    private DebugTranscriptInjectionRunner? debugTranscriptInjection;
#endif
    private bool isExiting;

    public App()
    {
        WindowsScreenshotDpi.EnablePerMonitorV2();
        startupDiagnostics = new StartupDiagnosticLog(
            StartupDiagnosticLog.DefaultLogPath);
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
        startupDiagnostics.Record("process.started");
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        startupDiagnostics.Record("startup.begin");
        try
        {
            singleInstance = WindowsSingleInstanceCoordinator.Start(
                WindowsSingleInstanceCoordinator.DefaultIdentity,
                OnSecondaryInstanceActivationRequested);
            if (!singleInstance.IsPrimary)
            {
                startupDiagnostics.Record(
                    singleInstance.ActivationSignaled
                        ? "startup.secondary_instance signaled=true"
                        : "startup.secondary_instance signaled=false");
                singleInstance.Dispose();
                singleInstance = null;
                Shutdown(0);
                return;
            }
            InitializeApplication(e);
            startupDiagnostics.Record("startup.completed");
        }
        catch (Exception exception)
        {
            startupDiagnostics.Record("startup.failed", exception);
            throw;
        }
    }

    private void InitializeApplication(StartupEventArgs e)
    {
        var dataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow");
        generalPreferenceStore = new GeneralPreferenceStore(
            Path.Combine(dataRoot, "ui", "general.json"));
        generalPreferences = generalPreferenceStore.Load();
        ApplyUiLanguage(generalPreferences.UiLanguageId);

        var preferencePath = Path.Combine(
            dataRoot,
            "ui",
            "theme.txt");
        themeManager = new ThemeManager(
            Resources,
            new FileThemePreferenceStore(preferencePath));
        themeManager.Initialize();

        base.OnStartup(e);

        composition = new WindowsAppCompositionRoot(
            Path.Combine(dataRoot, "voxflow.db"),
            textRefiner: null,
            interactiveFeatureFlags: new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true));
        try
        {
            startupDiagnostics.Record(
                ScreenshotReadinessDiagnostics
                    .Capture(composition.ScreenshotFrames, AppContext.BaseDirectory)
                    .ToSafeDiagnosticCode());
        }
        catch
        {
            // Readiness logging must never prevent startup or disclose an
            // exception that could contain a display name or installation path.
            startupDiagnostics.Record("screenshot.readiness probe=failed");
        }
        sharedState = new SharedAppStateProjection(
            composition.StateStore,
            selectionTransformsAvailable: composition.SelectionTransformService is not null);
        settingsCoordinator = new SettingsStateCoordinator(composition.StateStore);
        var launchAtLogin = new WindowsLaunchAtLoginService();
        var generalSettingsActions = new GeneralSettingsActions(
            () => themeManager?.CurrentMode == AppThemeMode.Dark,
            enabled => (themeManager
                ?? throw new InvalidOperationException("Theme manager is unavailable."))
                .Apply(enabled ? AppThemeMode.Dark : AppThemeMode.Light),
            launchAtLogin.IsEnabled,
            launchAtLogin.SetEnabled,
            startupDiagnostics.CreateSanitizedReport,
            text => System.Windows.Clipboard.SetText(text),
            ReadGrayTrayIcon: () => generalPreferences.GrayTrayIcon,
            ApplyGrayTrayIcon: enabled =>
            {
                SaveGeneralPreferences(generalPreferences with { GrayTrayIcon = enabled });
                trayIcon?.ApplyGrayMode(enabled);
            },
            ReadCapsLockIndicator: () => generalPreferences.CapsLockIndicator,
            ApplyCapsLockIndicator: enabled =>
            {
                SaveGeneralPreferences(generalPreferences with { CapsLockIndicator = enabled });
                hudWindow?.SetCapsLockIndicatorEnabled(enabled);
            },
            ReadStreamPreview: () => generalPreferences.StreamPreview,
            ApplyStreamPreview: enabled =>
                SaveGeneralPreferences(generalPreferences with { StreamPreview = enabled }),
            ReadAutoReleaseModels: () => generalPreferences.AutoReleaseModels,
            ApplyAutoReleaseModels: enabled =>
                SaveGeneralPreferences(generalPreferences with { AutoReleaseModels = enabled }),
            ReadUiLanguage: () => generalPreferences.UiLanguageId,
            ApplyUiLanguage: languageId =>
            {
                SaveGeneralPreferences(generalPreferences with { UiLanguageId = languageId });
                ApplyUiLanguage(languageId);
            });
        settingsPage = new SettingsPageViewModel(
            L10n.Localize("SettingsHeading"),
            L10n.Localize("SettingsSubtitle"),
            composition.StateStore,
            composition.TextSettingsStore,
            composition.OpenAiSettingsService,
            composition.CloudAsrSettings,
            composition.LlmProviderManagement,
            composition.InteractiveHotkeySettingsStore,
            composition.InteractiveFeatures.Flags,
            composition.QwenCatalog,
            composition.QwenModels,
            composition.QwenModelOperations,
            composition.BuiltinAgentRuntime,
            bindings =>
            {
                composition.UpdateInteractiveHotkeyBindings(bindings);
                var projection = VoiceRuntimeSettingsProjection.From(
                    composition.StateStore.Current);
                dictationRuntime?.UpdateHotkeySettings(projection.Hotkey with
                {
                    PrimaryBinding = bindings.Dictation,
                });
            },
            generalSettingsActions,
            composition.ScreenshotAutomationSettingsStore,
            enabled => clipboardImageOcrEnabled = enabled
#if DEBUG
            , RunDebugTranscriptInjectionAsync
#endif
            );
        // Restore durable ASR selection (and cloud credential readiness) before
        // the hotkey runtime starts. Without this, Right Ctrl reports
        // "no speech recognizer is ready" even when Tencent credentials exist.
        composition.BootstrapAsrAsync(CancellationToken.None)
            .GetAwaiter()
            .GetResult();
        settingsPage.InitializeAsync(CancellationToken.None).GetAwaiter().GetResult();
        var selectedAsr = composition.ReadSelectedAsrSelection();
        startupDiagnostics.Record(
            selectedAsr is null
                ? "asr.bootstrap.unconfigured"
                : $"asr.bootstrap.selected provider={selectedAsr.Provider} variant={selectedAsr.QwenVariant?.ToString() ?? "none"}");

        homeDashboard = new HomeDashboardViewModel(
            composition.HistoryStore,
            new WpfTextClipboardWriter(),
            TimeProvider.System,
            reprocessor: composition.HistoryReprocessor,
            unifiedHistory: composition.UnifiedHistory,
            screenshotAssets: composition.ScreenshotAssets);
        homeDashboard.Reload();
        screenshotMediaPage = new ScreenshotMediaPageViewModel(
            L10n.Localize("ScreenshotMediaHeading"),
            L10n.Localize("ScreenshotMediaSubtitle"),
            composition.ScreenshotRecords,
            composition.ScreenshotAssets,
            transformCacheInvalidator: composition.ScreenshotTransformCacheInvalidator);
        screenshotMediaPage.StartScreenshotRequested += OnStartScreenshotRequested;
        screenshotMediaPage.ReprocessRequested += OnReprocessScreenshotRequested;
        if (composition.ScreenshotTransformPersistence is { } screenshotTransformPersistence)
        {
            screenshotTransformPersistence.RecordUpdated += OnScreenshotRecordUpdated;
        }
        _ = screenshotMediaPage.RefreshAsync(CancellationToken.None);
        screenshotController = CreateScreenshotController(composition);
        clipboardImageOcr = CreateClipboardImageOcrService(composition);
        try
        {
            clipboardImageWatcher = new ClipboardImageWatcher(
                Dispatcher,
                () => clipboardImageOcrEnabled,
                token => clipboardImageOcr.RunFromClipboardChangeAsync(token));
            clipboardImageWatcher.Start();
        }
        catch (Exception exception)
        {
            startupDiagnostics.Record("clipboard.watcher.start_failed", exception);
            clipboardImageWatcher?.Dispose();
            clipboardImageWatcher = null;
        }
        var window = new MainWindow(
            homeDashboard,
            settingsPage,
            composition.CreateFileTranscriptionPageViewModel(),
            screenshotMediaPage,
            composition.ScreenshotCaptureLifecycle.HandleWindowMessage,
            composition.GlossaryStore,
            composition.WritingStyleStore,
            composition.GlossarySuggestions);
        MainWindow = window;
        window.Closing += OnMainWindowClosing;
        RefreshAgentTrayState();
        trayIcon = new WindowsTrayIcon(
            sharedState,
            ExecuteTrayCommand,
            RefreshAgentTrayState);
        trayIcon.ApplyGrayMode(generalPreferences.GrayTrayIcon);
        window.Show();
        if (secondaryActivationPending)
        {
            secondaryActivationPending = false;
            ShowMainWindow(openSettings: false);
        }
        InitializeDictationRuntime();
    }

    private WindowsScreenshotController CreateScreenshotController(
        WindowsAppCompositionRoot root)
    {
        var transforms = root.ScreenshotTransforms
            ?? throw new InvalidOperationException(
                "Screenshot transforms were not composed for the enabled interactive feature set.");
        var persistence = root.ScreenshotTransformPersistence is { } coordinator
            ? new ScreenshotResultTransformPersistenceAdapter(coordinator)
            : null;
        var presenter = new ScreenshotResultPresenter(
            transforms,
            new ScreenshotAssetStoreResultResolver(root.ScreenshotAssets),
            new WpfScreenshotResultClipboard(),
            new FallbackScreenshotSpeechBackend(
                local: null,
                new WindowsSystemScreenshotSpeechBackend()),
            persistence);
        var pipeline = new ScreenshotSelectionPipeline(
            root.ScreenshotRenderer,
            new ScreenshotThumbnailEncoder(),
            new ScreenshotClipboardService(),
            new ScreenshotExportService(
                new WindowsScreenshotSaveDialog(() =>
                    Windows.OfType<MainWindow>().FirstOrDefault(window => window.IsVisible)),
                new AtomicScreenshotPngWriter(),
                new ScreenshotDefaultFileNameProvider()),
            root.ScreenshotCompletion,
            presenter,
            TimeProvider.System,
            completed =>
            {
                if (completed.Record is { } record && screenshotMediaPage is { } media)
                {
                    _ = media.NotifyRecordUpdatedAsync(record.Id);
                }
            });
        return new WindowsScreenshotController(
            Dispatcher,
            new Dx11ScreenshotDesktopCapture(root.ScreenshotFrames),
            new WpfScreenshotOverlaySession(
                root.ScreenshotInlineTranslation,
                screenshotKeyboardRouter),
            pipeline,
            root.ScreenshotRuns,
            root.ScreenshotWorkflows,
            () => dictationRuntime?.IsVoiceWorkflowActive == true,
            ReportScreenshotFailure);
    }

    private ClipboardImageOcrService CreateClipboardImageOcrService(
        WindowsAppCompositionRoot root)
    {
        var transforms = root.ScreenshotTransforms
            ?? throw new InvalidOperationException(
                "Screenshot transforms were not composed for the enabled interactive feature set.");
        var persistence = root.ScreenshotTransformPersistence is { } coordinator
            ? new ScreenshotResultTransformPersistenceAdapter(coordinator)
            : null;
        var presenter = new ScreenshotResultPresenter(
            transforms,
            new ScreenshotAssetStoreResultResolver(root.ScreenshotAssets),
            new WpfScreenshotResultClipboard(),
            new FallbackScreenshotSpeechBackend(
                local: null,
                new WindowsSystemScreenshotSpeechBackend()),
            persistence);
        return new ClipboardImageOcrService(
            Dispatcher,
            root.ScreenshotCompletion,
            presenter,
            root.ScreenshotRuns,
            root.ScreenshotWorkflows,
            () => clipboardImageOcrEnabled,
            () => dictationRuntime?.IsVoiceWorkflowActive == true,
            completed =>
            {
                if (completed.Record is { } record && screenshotMediaPage is { } media)
                {
                    _ = media.NotifyRecordUpdatedAsync(record.Id);
                }
                homeDashboard?.Reload();
            },
            ReportScreenshotFailure);
    }

    private void OnStartScreenshotRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        _ = screenshotController?.StartAsync();
    }

    private void OnReprocessScreenshotRequested(object? sender, string screenshotId)
    {
        _ = sender;
        screenshotReprocessCancellation?.Cancel();
        screenshotReprocessCancellation?.Dispose();
        screenshotReprocessCancellation = new CancellationTokenSource();
        _ = ReprocessScreenshotAsync(
            screenshotId,
            screenshotReprocessCancellation.Token);
    }

    private async Task ReprocessScreenshotAsync(
        string screenshotId,
        CancellationToken cancellationToken)
    {
        if (composition is null || screenshotMediaPage is null)
        {
            return;
        }
        try
        {
            var record = composition.ScreenshotRecords.Get(screenshotId);
            if (record is null)
            {
                ReportScreenshotFailure("screenshot.reprocess.failed", null);
                return;
            }
            var imagePath = composition.ScreenshotAssets.ResolveAbsolutePath(
                record.RenderedImagePath);
            var recognized = await composition.ScreenshotOcrEngine.RecognizeAsync(
                new ScreenshotOcrEngineRequest(
                    imagePath,
                    System.Globalization.CultureInfo.CurrentUICulture.Name),
                cancellationToken);
            if (recognized.Status is not (
                ScreenshotOcrEngineStatus.Succeeded
                or ScreenshotOcrEngineStatus.Empty))
            {
                ReportScreenshotFailure("screenshot.reprocess.failed", null);
                return;
            }
            if (!composition.ScreenshotRecords.ReplaceOcrAndInvalidateTransforms(
                    screenshotId,
                    recognized.Text,
                    TimeProvider.System.GetUtcNow()))
            {
                ReportScreenshotFailure("screenshot.reprocess.failed", null);
                return;
            }
            await screenshotMediaPage.NotifyRecordUpdatedAsync(
                screenshotId,
                cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Starting another reprocess or exiting intentionally cancels this run.
        }
        catch (Exception exception)
        {
            ReportScreenshotFailure("screenshot.reprocess.failed", exception);
        }
    }

    private void ReportScreenshotFailure(string safeMessage, Exception? exception)
    {
        startupDiagnostics.Record("screenshot.failed:" + safeMessage, exception);
        var message = safeMessage switch
        {
            "screenshot.capture.busy" => L10n.Localize("ScreenshotCaptureBusy"),
            "screenshot.reprocess.failed" => L10n.Localize("ScreenshotReprocessFailed"),
            "screenshot.capture.failed" => L10n.Localize("ScreenshotCaptureFailed"),
            "clipboard.ocr.no_image" => L10n.Localize("ClipboardImageOcrNoImage"),
            "clipboard.ocr.no_text" => L10n.Localize("ClipboardImageOcrNoText"),
            "clipboard.ocr.disabled" => L10n.Localize("ClipboardImageOcrDisabled"),
            "screenshot.persistence.asset_failed" or
            "screenshot.persistence.record_failed" =>
                L10n.Localize("ScreenshotProcessingFailed"),
            _ when !safeMessage.StartsWith("screenshot.", StringComparison.Ordinal)
                && !safeMessage.StartsWith("clipboard.", StringComparison.Ordinal) => safeMessage,
            _ => L10n.Localize("ScreenshotProcessingFailed"),
        };
        VoxFlowDialogWindow.ShowMessage(
            MainWindow,
            L10n.Localize("ScreenshotResultTitle"),
            message,
            VoxFlowDialogKind.Warning);
    }

    private async void OnScreenshotRecordUpdated(
        object? sender,
        ScreenshotRecordUpdatedEventArgs eventArgs)
    {
        _ = sender;
        var media = screenshotMediaPage;
        var home = homeDashboard;

        try
        {
            if (Dispatcher.CheckAccess())
            {
                if (media is not null)
                {
                    await media.NotifyRecordUpdatedAsync(eventArgs.ScreenshotId);
                }

                home?.Reload();
                return;
            }

            await Dispatcher.InvokeAsync(async () =>
            {
                if (media is not null)
                {
                    await media.NotifyRecordUpdatedAsync(eventArgs.ScreenshotId);
                }

                home?.Reload();
            }).Task.Unwrap();
        }
        catch (OperationCanceledException)
        {
            // Refresh cancellation is non-destructive; the next media refresh reads persisted data.
        }
        catch (Exception exception)
        {
            startupDiagnostics.Record("screenshot.media.refresh_failed", exception);
        }
    }

    private void SaveGeneralPreferences(GeneralPreferenceDocument value)
    {
        var normalized = value.Normalize();
        (generalPreferenceStore
            ?? throw new InvalidOperationException("General preference store is unavailable."))
            .Save(normalized);
        generalPreferences = normalized;
    }

    private static void ApplyUiLanguage(string languageId)
    {
        var culture = languageId switch
        {
            "zh-Hans" => CultureInfo.GetCultureInfo("zh-Hans"),
            "zh-Hant" => CultureInfo.GetCultureInfo("zh-Hant"),
            "en" => CultureInfo.GetCultureInfo("en"),
            "ja" => CultureInfo.GetCultureInfo("ja"),
            "ko" => CultureInfo.GetCultureInfo("ko"),
            _ => CultureInfo.InstalledUICulture,
        };
        CultureInfo.DefaultThreadCurrentUICulture = culture;
        Thread.CurrentThread.CurrentUICulture = culture;
    }

    private void OnDictationPhaseChanged(DictationPhase phase)
    {
        if (phase != DictationPhase.Idle
            || !generalPreferences.AutoReleaseModels
            || composition is not { } root)
        {
            return;
        }
        _ = ReleaseSelectedLocalModelAsync(root);
    }

    private async Task ReleaseSelectedLocalModelAsync(WindowsAppCompositionRoot root)
    {
        try
        {
            await root.ReleaseSelectedLocalModelAsync(CancellationToken.None);
            startupDiagnostics.Record("qwen.runtime.auto_released");
        }
        catch (Exception exception)
        {
            startupDiagnostics.Record("qwen.runtime.auto_release_failed", exception);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        startupDiagnostics.Record("process.exiting");
        if (composition?.ScreenshotTransformPersistence is { } screenshotTransformPersistence)
        {
            screenshotTransformPersistence.RecordUpdated -= OnScreenshotRecordUpdated;
        }
        if (screenshotMediaPage is not null)
        {
            screenshotMediaPage.StartScreenshotRequested -= OnStartScreenshotRequested;
            screenshotMediaPage.ReprocessRequested -= OnReprocessScreenshotRequested;
            screenshotMediaPage = null;
        }
        clipboardImageWatcher?.Dispose();
        clipboardImageWatcher = null;
        clipboardImageOcr?.Dispose();
        clipboardImageOcr = null;
        screenshotController?.Dispose();
        screenshotController = null;
        screenshotReprocessCancellation?.Cancel();
        screenshotReprocessCancellation?.Dispose();
        screenshotReprocessCancellation = null;
        if (dictationRuntime is not null)
        {
            dictationRuntime.DisposeAsync().AsTask().GetAwaiter().GetResult();
            dictationRuntime = null;
        }
        selectionTransforms?.Dispose();
        selectionTransforms = null;
#if DEBUG
        debugTranscriptInjection = null;
#endif
        hudWindow?.Close();
        hudWindow = null;
        trayIcon?.Dispose();
        trayIcon = null;
        sharedState?.Dispose();
        sharedState = null;
        composition?.Dispose();
        composition = null;
        singleInstance?.Dispose();
        singleInstance = null;
        DispatcherUnhandledException -= OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException -= OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException -= OnUnobservedTaskException;
        base.OnExit(e);
    }

    private void InitializeDictationRuntime()
    {
        if (composition is null)
        {
            throw new InvalidOperationException("Application composition is unavailable.");
        }

        hudWindow = new HudWindow();
        hudWindow.SetCapsLockIndicatorEnabled(generalPreferences.CapsLockIndicator);
        var workArea = SystemParameters.WorkArea;
        const double hudWidth = 520;
        const double hudHeight = 64;
        hudWindow.ApplyPlacement(
            workArea.Left + ((workArea.Width - hudWidth) / 2),
            workArea.Bottom - hudHeight - 40,
            hudWidth,
            hudHeight);
        var progress = new HudDictationProgressSink(
            action =>
            {
                if (Dispatcher.CheckAccess())
                {
                    action();
                }
                else
                {
                    _ = Dispatcher.BeginInvoke(action);
                }
            },
            hudWindow.UpdatePresentation,
            showPartialText: () => generalPreferences.StreamPreview,
            phaseChanged: OnDictationPhaseChanged);
        var agentProgress = new HudDictationProgressSink(
            action =>
            {
                if (Dispatcher.CheckAccess())
                {
                    action();
                }
                else
                {
                    _ = Dispatcher.BeginInvoke(action);
                }
            },
            hudWindow.UpdatePresentation,
            isAgentCompose: true,
            agentPhaseChanged: phase => settingsCoordinator?.RecordAgentPhase(phase));
        var audio = new WasapiDictationAudioCaptureAdapter(
            new WasapiMicrophoneCapture(),
            () => VoiceRuntimeSettingsProjection
                .From(composition.StateStore.Current)
                .Audio);
        var clipboard = new WindowsClipboardGateway();
        var quickPaste = new QuickPasteService(
            clipboard,
            new WindowsPasteShortcutSender());
        var quickPasteInjector = new QuickPasteOutputInjector(quickPaste);
        var simulatedTyping = new SimulatedTypingService(
            new WindowsUnicodeInputSender(),
            quickPaste);
        var output = new WindowsTextOutputCoordinator(
            new SettingsAwareTextOutputInjector(
                () => VoiceRuntimeSettingsProjection
                    .From(composition.StateStore.Current)
                    .OutputModeId,
                quickPasteInjector,
                new SimulatedTypingOutputInjector(simulatedTyping)),
            new WindowsOutputClipboardCopier(clipboard),
            new ForegroundTargetOutputGuard(new Win32ForegroundTargetProvider()));
        var history = new DictationHistoryStoreSink(
            composition.HistoryStore,
            TimeProvider.System,
            composition.ReadSelectedAsrSelection);
        var orchestrator = composition.CreateDictationOrchestrator(
            composition.CreateSelectedDictationProvider(),
            audio,
            output,
            history,
            progress,
            TimeProvider.System,
            TimeSpan.FromSeconds(15));
        DictationOrchestrator? agentOrchestrator = null;
        WasapiDictationAudioCaptureAdapter? agentAudio = null;
        WindowsClipboardGateway? agentClipboard = null;
        AgentComposeWorkflowTracker? agentWorkflow = null;
        AgentComposeContextCapture? agentContext = null;
        AgentComposeDictationPostProcessor? agentProcessor = null;
        if (composition.AgentComposeExecution is { } agentExecution)
        {
            agentClipboard = new WindowsClipboardGateway();
            agentAudio = new WasapiDictationAudioCaptureAdapter(
                new WasapiMicrophoneCapture(),
                () => VoiceRuntimeSettingsProjection
                    .From(composition.StateStore.Current)
                    .Audio);
            agentWorkflow = composition.WorkflowTaskService is { } workflowTaskService
                ? new AgentComposeWorkflowTracker(
                    workflowTaskService,
                    HistoryRetentionPolicy.Default,
                    TimeProvider.System,
                    composition.ReadSelectedAsrSelection)
                : null;
            var sessionsRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "VoxFlow",
                "AgentRuntime",
                "sessions");
            agentContext = new AgentComposeContextCapture(
                new WindowsAgentTargetSnapshotProvider(),
                new AgentContextPipeline(new WindowsAgentContextReader(
                    new WindowsUiAutomationSelectionProbeProvider(),
                    TimeProvider.System),
                    new WindowsAgentVisualTextFallback()),
                agentWorkflow,
                agentProgress.ShowAgentReadingWindow,
                taskId => Path.Combine(sessionsRoot, taskId));
            var agentOutput = new AgentComposeOutputCoordinator(
                new WindowsAgentOutputClipboard(agentClipboard),
                new HudAgentOutputSummaryPresenter(agentProgress));
            agentProcessor = new AgentComposeDictationPostProcessor(
                agentContext,
                agentExecution,
                taskId => Path.Combine(sessionsRoot, taskId),
                composition.HistoryStore,
                eventSink: agentProgress.PublishAgentSidecarEvent,
                output: agentOutput,
                workflow: agentWorkflow,
                sessionWorkspaces: composition.AgentSessionWorkspaces);
            agentOrchestrator = composition.CreateDictationOrchestrator(
                composition.CreateSelectedDictationProvider(),
                agentAudio,
                new DiscardingAgentDictationOutput(),
                new DiscardingAgentDictationHistorySink(),
                agentProgress,
                TimeProvider.System,
                TimeSpan.FromSeconds(15),
                processor: agentProcessor,
                targetCapture: agentContext);
        }
        var voiceSettings = VoiceRuntimeSettingsProjection.From(
            composition.StateStore.Current);
        voiceSettings = voiceSettings with
        {
            Hotkey = voiceSettings.Hotkey with
            {
                PrimaryBinding = composition.InteractiveHotkeyBindings?.Dictation
                    ?? HotkeyBinding.RightControlDefault,
            },
        };
        if (composition.SelectionTransformService is { } transformService)
        {
            selectionTransforms = new SelectionTransformWindowController(
                Dispatcher,
                transformService,
                ReportSelectionFailure);
        }
        dictationRuntime = new WindowsDictationDesktopRuntime(
            Dispatcher,
            orchestrator,
            audio,
            clipboard,
            voiceSettings.Hotkey,
            startupDiagnostics,
            composition.InteractiveHotkeyRoute,
            HandleInteractiveHotkeyAsync,
            agentOrchestrator,
            agentAudio,
            agentClipboard,
            agentWorkflow is null ? null : agentWorkflow.RecordCancellation,
            composition.ReadAgentComposeReadinessAsync,
            agentProgress.ShowAgentUnavailable,
            IsForegroundInteractionBusy,
            screenshotKeyboardRouter,
            () => VoiceRuntimeSettingsProjection.From(
                composition.StateStore.Current).Hotkey with
                {
                    PrimaryBinding = composition.InteractiveHotkeyBindings?.Dictation
                        ?? HotkeyBinding.RightControlDefault,
                });
#if DEBUG
        debugTranscriptInjection = new DebugTranscriptInjectionRunner(
            (transcript, mode) => mode switch
            {
                DebugTranscriptInjectionMode.Dictation =>
                    composition.CreateDictationOrchestrator(
                        new DebugTranscriptAsrProvider(transcript),
                        new DebugSilentAudioCapture(),
                        output,
                        history,
                        progress,
                        TimeProvider.System,
                        TimeSpan.FromSeconds(15)),
                DebugTranscriptInjectionMode.AgentCompose
                    when agentProcessor is not null && agentContext is not null =>
                    composition.CreateDictationOrchestrator(
                        new DebugTranscriptAsrProvider(transcript),
                        new DebugSilentAudioCapture(),
                        new DiscardingAgentDictationOutput(),
                        new DiscardingAgentDictationHistorySink(),
                        agentProgress,
                        TimeProvider.System,
                        TimeSpan.FromSeconds(15),
                        processor: agentProcessor,
                        targetCapture: agentContext),
                _ => null,
            });
#endif
        _ = dictationRuntime.Start();
        RefreshAgentTrayState();
    }

    private bool IsForegroundInteractionBusy() =>
        screenshotController?.IsActive == true
#if DEBUG
        || debugTranscriptInjection?.IsBusy == true
#endif
        ;

#if DEBUG
    private Task<DebugTranscriptInjectionResult> RunDebugTranscriptInjectionAsync(
        string transcript,
        DebugTranscriptInjectionMode mode,
        CancellationToken cancellationToken)
    {
        if (IsForegroundInteractionBusy()
            || dictationRuntime?.IsVoiceWorkflowActive == true)
        {
            return Task.FromResult(new DebugTranscriptInjectionResult(
                DebugTranscriptInjectionStatus.Busy));
        }
        return debugTranscriptInjection?.RunAsync(transcript, mode, cancellationToken)
            ?? Task.FromResult(new DebugTranscriptInjectionResult(
                DebugTranscriptInjectionStatus.Unavailable));
    }
#endif

    private Task HandleInteractiveHotkeyAsync(
        InteractiveHotkeyRouteEvent route,
        CancellationToken cancellationToken) => route.Action switch
    {
        InteractiveHotkeyAction.Screenshot =>
            screenshotController?.StartAsync(cancellationToken)
                ?? Task.CompletedTask,
        InteractiveHotkeyAction.ClipboardImageOcr =>
            clipboardImageOcr?.RunFromHotkeyAsync(cancellationToken)
                ?? Task.CompletedTask,
        InteractiveHotkeyAction.SelectionTranslation =>
            RunSelectionTransformAsync(
                SelectionTransformOperation.Refine,
                cancellationToken),
        InteractiveHotkeyAction.SelectionSummary =>
            RunSelectionTransformAsync(
                SelectionTransformOperation.Summary,
                cancellationToken),
        InteractiveHotkeyAction.SelectionAskAi =>
            RunSelectionTransformAsync(
                SelectionTransformOperation.AskAi,
                cancellationToken),
        _ => Task.CompletedTask,
    };

    private void OnDispatcherUnhandledException(
        object sender,
        DispatcherUnhandledExceptionEventArgs e) =>
        startupDiagnostics.Record("exception.dispatcher_unhandled", e.Exception);

    private void OnDomainUnhandledException(
        object? sender,
        UnhandledExceptionEventArgs e) =>
        startupDiagnostics.Record(
            e.IsTerminating
                ? "exception.appdomain_terminating"
                : "exception.appdomain_unhandled",
            e.ExceptionObject as Exception
                ?? new Exception(e.ExceptionObject?.ToString() ?? "Unknown exception"));

    private void OnUnobservedTaskException(
        object? sender,
        UnobservedTaskExceptionEventArgs e) =>
        startupDiagnostics.Record("exception.task_unobserved", e.Exception);

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
            case "agent.start":
                _ = RunTrayAgentActionAsync(start: true);
                break;
            case "agent.stop":
                _ = RunTrayAgentActionAsync(start: false);
                break;
            case "screenshot.start":
                _ = screenshotController?.StartAsync();
                break;
            case "selection.translate":
                _ = RunSelectionTransformAsync(SelectionTransformOperation.Translation);
                break;
            case "selection.summary":
                _ = RunSelectionTransformAsync(SelectionTransformOperation.Summary);
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

    private async Task RunSelectionTransformAsync(
        SelectionTransformOperation operation,
        CancellationToken cancellationToken = default)
    {
        if (screenshotController?.IsActive == true)
        {
            ReportSelectionFailure(L10n.Localize("SelectionUnavailableDuringScreenshot"));
            return;
        }

        if (selectionTransforms is null)
        {
            ReportSelectionFailure(L10n.Localize("SelectionFailureUnexpected"));
            return;
        }

        try
        {
            await selectionTransforms.StartAsync(operation, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Cancellation is expected when a hotkey workflow is superseded.
        }
        catch (Exception exception)
        {
            startupDiagnostics.Record("selection.failed", exception);
            ReportSelectionFailure(L10n.Localize("SelectionFailureUnexpected"));
        }
    }

    private void ReportSelectionFailure(string message)
    {
        if (!Dispatcher.CheckAccess())
        {
            _ = Dispatcher.BeginInvoke(() => ReportSelectionFailure(message));
            return;
        }

        startupDiagnostics.Record("selection.failed");
        VoxFlowDialogWindow.ShowMessage(
            MainWindow,
            L10n.BrandName,
            message,
            VoxFlowDialogKind.Warning);
    }

    private void RefreshAgentTrayState()
    {
        if (composition is null || settingsCoordinator is null)
        {
            return;
        }

        var provider = composition.LlmProviderManagement?
            .List()
            .FirstOrDefault(candidate => candidate.IsDefault && candidate.Enabled);
        settingsCoordinator.RecordAgentReadiness(
            runtimeAvailable: composition.BuiltinAgentRuntime?.IsAvailable == true,
            providerConfigured: provider is not null,
            connectionHealthy: provider?.HealthStatus == LlmProviderHealthStatus.Ok,
            toolCallingSupported: provider?.AgentCapabilityStatus == LlmAgentCapabilityStatus.Supported);
    }

    private async Task RunTrayAgentActionAsync(bool start)
    {
        RefreshAgentTrayState();
        var runtime = dictationRuntime;
        var agent = sharedState?.Current.TrayMenu.Agent;
        if (runtime is null || agent is null || (start && !agent.IsReady))
        {
            return;
        }

        try
        {
            if (start)
            {
                await runtime.StartAgentComposeAsync().ConfigureAwait(true);
            }
            else
            {
                await runtime.StopAgentComposeAsync().ConfigureAwait(true);
            }
        }
        catch (OperationCanceledException)
        {
            // An explicit tray stop has normal cancellation semantics.
        }
        catch (Exception exception)
        {
            startupDiagnostics.Record("agent.tray_action_failed", exception);
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
                composition?.CreateFileTranscriptionPageViewModel(),
                screenshotMediaPage,
                composition is null
                    ? null
                    : composition.ScreenshotCaptureLifecycle.HandleWindowMessage,
                composition?.GlossaryStore,
                composition?.WritingStyleStore,
                composition?.GlossarySuggestions);
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

    private void OnSecondaryInstanceActivationRequested()
    {
        _ = Dispatcher.BeginInvoke(() =>
        {
            if (MainWindow is null)
            {
                secondaryActivationPending = true;
                return;
            }
            ShowMainWindow(openSettings: false);
        });
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
