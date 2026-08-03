using System.Net.Http;
using System.IO;
using System.Buffers.Binary;
using System.Runtime.InteropServices;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Application.SelectionTransform;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Infrastructure.Screenshots;
using VoxFlow.Windows.Infrastructure.Security;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Infrastructure.Media;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Files;
using VoxFlow.Windows.Platform.Audio;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Providers.Cloud.OpenAI;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;
using VoxFlow.Windows.Providers.Qwen;
using VoxFlow.Windows.Providers.Qwen.Models;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;

namespace VoxFlow.Windows.App.Composition;

/// <summary>
/// Owns the Windows application's process-wide persistence and conservative
/// text pipeline. Provider selection supplies the outer ASR session, while all
/// providers share this same post-processing path.
/// </summary>
public sealed class WindowsAppCompositionRoot : IDisposable
{
    private readonly SqliteTransactionRunner transactionRunner;
    private readonly SqliteCredentialVault credentialVault;
    private readonly HttpClient httpClient;
    private readonly IDictationTextPostProcessor textProcessor;
    private readonly SqliteFileTranscriptionJobRepository fileTranscriptionJobs;
    private readonly SqliteFileTranscriptionSegmentRepository fileTranscriptionSegments;
    private readonly FileTranscriptionQueueService fileTranscriptionQueue;
    private readonly FileTranscriptionJobLifecycleService fileTranscriptionLifecycle;
    private readonly FileTranscriptionCopyService fileTranscriptionCopy;
    private readonly FileTranscriptionExportService fileTranscriptionExport;
    private readonly FileTranscriptionTranslationService fileTranscriptionTranslation;
    private readonly FileTranscriptionStateProjection fileTranscriptionState;
    private readonly FileTranscriptionPlaybackService fileTranscriptionPlayback;
    private readonly QwenDictationProviderRuntime qwenRuntime;
    private readonly QwenNativeModelReadinessHost qwenReadinessHost;
    private readonly TencentAsrSettingsService tencentAsrSettings;
    private readonly AliyunAsrSettingsService aliyunAsrSettings;
    private readonly VolcengineAsrSettingsService volcengineAsrSettings;
    private readonly ICloudWebSocketFactory cloudSocketFactory;
    private readonly IDefaultLlmProviderResolver? agentProviderResolver;
    private readonly WindowsClipboardGateway? agentToolClipboard;
    private readonly AgentWebFetchClient? agentWebFetchClient;
    private readonly AgentWebSearchClient? agentWebSearchClient;
    private readonly SqliteAsrSelectionStore asrSelectionStore;
    private readonly SettingsStateCoordinator asrStateCoordinator;
    private readonly IDisposable asrSelectionPersistence;
    private int disposed;

    public WindowsAppCompositionRoot(
        string databasePath,
        IStreamingTextRefiner? textRefiner = null)
        : this(databasePath, textRefiner, interactiveFeatureFlags: null)
    {
    }

    public WindowsAppCompositionRoot(
        string databasePath,
        IStreamingTextRefiner? textRefiner,
        WindowsInteractiveFeatureFlags? interactiveFeatureFlags)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(databasePath);
        var dataRoot = Path.GetDirectoryName(Path.GetFullPath(databasePath))
            ?? throw new ArgumentException(
                "The database must have a parent directory.",
                nameof(databasePath));
        var screenshotTemporaryRoot = Path.Combine(dataRoot, "Temp", "Screenshots");
        var screenshotOrientationTemporaryRoot = Path.Combine(
            Path.GetTempPath(),
            "VoxFlow",
            "ocr-orientation");
        var screenshotScratchDeleteBefore = TimeProvider.System.GetUtcNow().AddHours(-1);
        var screenshotScratchCleaner = new ScreenshotScratchFileCleaner();
        _ = screenshotScratchCleaner.CleanupInlineTranslationFiles(
            screenshotTemporaryRoot,
            screenshotScratchDeleteBefore);
        _ = screenshotScratchCleaner.CleanupOrientationFiles(
            screenshotOrientationTemporaryRoot,
            screenshotScratchDeleteBefore);
        InteractiveFeatures = new InteractiveFeatureDependencyGate(
            interactiveFeatureFlags ?? WindowsInteractiveFeatureFlags.Disabled);
        if (InteractiveFeatures.Flags.BuiltinAgentEnabled)
        {
            BuiltinAgentRuntime = new BuiltinAgentRuntimeVerifier()
                .Verify(AppContext.BaseDirectory);
        }
        AgentSessionWorkspaceRetentionService? agentSessionWorkspaces = null;
        new VoxFlowDatabaseMigrator(
            [
                .. InteractiveFeatureMigrationCatalog.For(InteractiveFeatures.Flags),
                .. ScreenshotMigrationCatalog.All(),
            ])
            .Migrate(databasePath);
        var connectionFactory = new SqliteConnectionFactory(databasePath, pooling: false);
        transactionRunner = new SqliteTransactionRunner(connectionFactory);
        credentialVault = new SqliteCredentialVault(
            connectionFactory,
            new DpapiCurrentUserDataProtector());
        ScreenshotRuns = new ScreenshotRunRegistry();
        var screenshotTransformCache = new ScreenshotTransformCache();
        ScreenshotTransformCacheInvalidator = screenshotTransformCache;
        ScreenshotRecords = new SqliteScreenshotRecordRepository(transactionRunner);
        ScreenshotAssets = new FileScreenshotAssetStore(dataRoot);
        ScreenshotMaintenance = new ScreenshotMaintenanceService(
            ScreenshotRecords,
            ScreenshotAssets,
            TimeProvider.System);
        ScreenshotMaintenanceResult = ScreenshotMaintenance
            .CleanupOnStartupAsync(
                HistoryRetentionPolicy.Default,
                CancellationToken.None)
            .GetAwaiter()
            .GetResult();
        ScreenshotOcrEngine = new TesseractScreenshotOcrAdapter(
            new TesseractRuntimeLocator(AppContext.BaseDirectory),
            new TesseractRuntimeVerifier(),
            new TesseractOcrProcessRunner());
        ScreenshotOcr = new ScreenshotOcrOrchestrator(
            ScreenshotOcrEngine,
            ScreenshotRuns);
        ScreenshotCompletion = new ScreenshotCompletionService(
            ScreenshotAssets,
            ScreenshotOcr,
            ScreenshotRecords,
            ScreenshotRuns);
        ScreenshotAutomationSettingsStore =
            new SqliteScreenshotAutomationSettingsStore(transactionRunner);
        ScreenshotFrames = new Dx11ScreenshotFrameSource();
        ScreenshotCaptureLifecycle = new WindowsScreenshotCaptureLifecycle(ScreenshotFrames);
        ScreenshotWorkflows = new InteractiveWorkflowCoordinator();
        ScreenshotRenderer = new ScreenshotSourceRenderer();
        if (InteractiveFeatures.Flags.SelectionTransformEnabled
            || InteractiveFeatures.Flags.BuiltinAgentEnabled)
        {
            _ = new LegacyOpenAiProviderMigration(
                    transactionRunner,
                    credentialVault,
                    TimeProvider.System)
                .RunAsync(CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            _ = new TokenHubDefaultModelMigration(
                    transactionRunner,
                    TimeProvider.System)
                .Run();
            WorkflowTasks = new SqliteWorkflowTaskRepository(transactionRunner);
            InteractiveHotkeySettingsStore =
                new SqliteInteractiveHotkeySettingsStore(transactionRunner);
            InteractiveHotkeyBindings = InteractiveHotkeyBindingSet.FromSettings(
                InteractiveHotkeySettingsStore
                    .LoadAsync(CancellationToken.None)
                    .AsTask()
                    .GetAwaiter()
                    .GetResult());
            InteractiveHotkeyRoute = new InteractiveHotkeyRoute(
                InteractiveHotkeyBindings);
            agentSessionWorkspaces = new AgentSessionWorkspaceRetentionService(
                new FileSystemAgentSessionWorkspaceStore(Path.Combine(
                    dataRoot,
                    "AgentRuntime",
                    "sessions")),
                TimeProvider.System);
            AgentSessionWorkspaces = agentSessionWorkspaces;
            WorkflowTaskService = new WorkflowTaskService(
                WorkflowTasks,
                TimeProvider.System,
                agentSessionWorkspaces: agentSessionWorkspaces);
            _ = WorkflowTaskService.CleanupOnStartup(HistoryRetentionPolicy.Default);
        }
        httpClient = new HttpClient
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };

        TextSettingsStore = new SqliteTextProcessingSettingsStore(transactionRunner);
        GlossaryStore = new SqliteGlossaryStore(transactionRunner);
        WritingStyleStore = new SqliteWritingStyleStore(transactionRunner);
        LlmSettingsStore = new SqliteLlmProviderSettingsStore(transactionRunner);
        HistoryStore = new SqliteHistoryStore(transactionRunner);
        GlossarySuggestions = new HistoryGlossarySuggestionSource(HistoryStore);
        StateStore = new VoxFlowStateStore();
        QwenCatalog = WindowsQwenManifestLoader.Load(Path.Combine(
            AppContext.BaseDirectory,
            "Qwen",
            "MODEL_PROVENANCE.json"));
        var modelRepository = new SqliteModelInstallStateRepository(transactionRunner);
        var modelSynchronizer = new QwenModelStateSynchronizer(StateStore);
        foreach (var manifest in QwenCatalog.Models)
        {
            var stored = modelRepository.LoadAsync(manifest.Id, CancellationToken.None)
                .AsTask()
                .GetAwaiter()
                .GetResult();
            var projected = stored is null
                ? new ModelInstallRecord(
                    manifest.Id,
                    manifest.ModelRevision,
                    manifest.RuntimeGate.IsPublishable
                        ? ModelInstallPhase.NotDownloaded
                        : ModelInstallPhase.RuntimeUnsupported,
                    0,
                    manifest.TotalBytes,
                    null,
                    manifest.RuntimeGate.IsPublishable
                        ? null
                        : "runtime_provenance_blocked")
                : manifest.RuntimeGate.IsPublishable
                    ? stored
                    : new ModelInstallRecord(
                        manifest.Id,
                        manifest.ModelRevision,
                        ModelInstallPhase.RuntimeUnsupported,
                        stored.BytesDownloaded,
                        manifest.TotalBytes,
                        stored.InstallPath,
                        "runtime_provenance_blocked");
            modelSynchronizer.Publish(manifest, projected);
        }

        QwenModels = new QwenModelEntryPointProjection(StateStore);

        var openAiClient = new OpenAiChatCompletionsClient(httpClient);
        OpenAiSettingsService = new OpenAiSettingsService(
            credentialVault,
            LlmSettingsStore,
            openAiClient);
        IDefaultLlmProviderResolver? managedTextProvider = null;
        ILlmStreamingClient? managedTextClient = null;
        if (InteractiveFeatures.Flags.AnyEnabled)
        {
            var providerRepository = new SqliteLlmProviderRepository(transactionRunner);
            var providerCredentialService = new LlmProviderCredentialService(
                credentialVault,
                providerRepository);
            var providerClient = new OpenAiCompatibleClient(
                httpClient,
                typeof(WindowsAppCompositionRoot).Assembly.GetName().Version?.ToString());
            LlmProviderManagement = new LlmProviderManagementService(
                providerRepository,
                providerCredentialService,
                providerClient);
            var defaultProvider = new DefaultLlmProviderResolver(
                providerRepository,
                providerCredentialService);
            managedTextProvider = defaultProvider;
            managedTextClient = providerClient;
            ScreenshotTransforms = new ScreenshotTransformService(
                defaultProvider,
                providerClient,
                screenshotTransformCache);
            ScreenshotTransformPersistence = new ScreenshotTransformPersistenceCoordinator(
                ScreenshotRecords,
                TimeProvider.System,
                ScreenshotRuns);
            agentProviderResolver = new AgentCapableLlmProviderResolver(
                providerRepository,
                defaultProvider);
            if (InteractiveFeatures.Flags.SelectionTransformEnabled)
            {
                SelectionTransformService = new SelectionTransformService(
                    defaultProvider,
                    providerClient);
            }
            if (InteractiveFeatures.Flags.BuiltinAgentEnabled
                && BuiltinAgentRuntime is { IsAvailable: true, Binary: { } binary })
            {
                agentToolClipboard = new WindowsClipboardGateway();
                agentWebFetchClient = new AgentWebFetchClient();
                agentWebSearchClient = new AgentWebSearchClient();
                AgentComposeExecution = new AgentComposeExecutionService(
                    agentProviderResolver,
                    new AgentComposePromptBuilder(),
                    new BuiltinAgentSidecarRunner(
                        new BuiltinAgentProcessSessionFactory(
                            new BuiltinAgentProcessHost(
                                new BuiltinAgentProcessSpecification(binary))),
                        new BuiltinAgentJsonlPump(new WpfAgentSidecarEventDispatcher())),
                    new WindowsAgentClipboardTextGateway(agentToolClipboard),
                    new WindowsAgentKeyboardGatewayFactory(),
                    new WindowsAgentUrlLauncher(),
                    new WindowsAgentTextFieldGatewayFactory(agentToolClipboard),
                    new AgentHttpRequestClient(httpClient),
                    agentWebFetchClient,
                    agentWebSearchClient,
                    new WpfAgentUserResponsePresenter(),
                    new WpfAgentQuestionPresenter());
            }
        }
        ScreenshotInlineTranslation = new ScreenshotInlineTranslationService(
            ScreenshotOcrEngine,
            ScreenshotTransforms,
            ScreenshotRuns,
            ScreenshotRenderer,
            screenshotTemporaryRoot);
        tencentAsrSettings = new TencentAsrSettingsService(
            credentialVault,
            new TencentSettingsConnectionTester());
        aliyunAsrSettings = new AliyunAsrSettingsService(
            credentialVault,
            new AliyunSettingsConnectionTester());
        volcengineAsrSettings = new VolcengineAsrSettingsService(credentialVault);
        asrSelectionStore = new SqliteAsrSelectionStore(transactionRunner);
        asrStateCoordinator = new SettingsStateCoordinator(StateStore);
        CloudAsrSettings = new CloudAsrSettingsCoordinator(
            tencentAsrSettings,
            aliyunAsrSettings,
            volcengineAsrSettings,
            asrStateCoordinator);
        asrSelectionPersistence = StateStore.Subscribe(
            OnAsrSelectionStateChanged,
            replayCurrent: false);
        WritingStyleApplicationContext? ReadWritingStyleContext()
        {
            var target = new Win32ForegroundTargetProvider().CaptureCurrent();
            return target is null
                ? null
                : new WritingStyleApplicationContext(
                    target.ProcessPath,
                    target.WindowTitle);
        }
        textRefiner ??= managedTextProvider is not null && managedTextClient is not null
            ? new OpenAiStreamingTextRefiner(
                managedTextProvider,
                managedTextClient,
                GlossaryStore,
                WritingStyleStore,
                ReadWritingStyleContext)
            : new OpenAiStreamingTextRefiner(
                credentialVault,
                LlmSettingsStore,
                openAiClient,
                GlossaryStore,
                WritingStyleStore,
                ReadWritingStyleContext);
        textProcessor = new ConfigurableTextProcessingPipeline(
            TextSettingsStore,
            new ConservativeLlmTextPostProcessor(textRefiner),
            GlossaryStore);
        HistoryReprocessor = new DictationHistoryReprocessor(textProcessor);

        fileTranscriptionJobs = new SqliteFileTranscriptionJobRepository(transactionRunner);
        fileTranscriptionSegments = new SqliteFileTranscriptionSegmentRepository(transactionRunner);
        qwenRuntime = new QwenDictationProviderRuntime(
            variant => IsQwenReady(modelRepository, variant),
            (variant, cancellationToken) => ResolveQwenModelPathAsync(
                modelRepository,
                variant,
                cancellationToken));
        qwenReadinessHost = new QwenNativeModelReadinessHost();
        var modelPaths = new QwenModelDataPaths(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        var runtimeReadiness = new ProvenanceGatedQwenRuntimeReadiness(qwenReadinessHost);
        var readiness = new QwenModelReadinessService(
            modelRepository,
            runtimeReadiness,
            modelSynchronizer,
            LoadReadinessCanary());
        QwenModelOperations = new QwenModelLifecycleOperations(
            modelPaths,
            new SystemModelDiskSpaceProbe(),
            new ResumableModelPackageDownloader(
                new ResumableModelFileDownloader(httpClient)),
            new QwenModelInstaller(new QwenModelIntegrityVerifier()),
            readiness,
            new QwenModelDeletionService(
                modelPaths,
                modelRepository,
                runtimeReadiness,
                modelSynchronizer),
            modelRepository,
            modelSynchronizer,
            modelSynchronizer);
        cloudSocketFactory = new ClientWebSocketFactory();
        var sessionFactory = new FileTranscriptionSessionFactory(
        [
            new QwenFileTranscriptionSessionAdapter(_ =>
                qwenRuntime.CreateProvider(SelectedQwenVariant())),
            new TencentFileTranscriptionSessionAdapter(
                tencentAsrSettings,
                cloudSocketFactory),
            new AliyunFileTranscriptionSessionAdapter(
                aliyunAsrSettings,
                cloudSocketFactory),
            new VolcengineFileTranscriptionSessionAdapter(
                volcengineAsrSettings,
                cloudSocketFactory),
        ]);
        var worker = new SessionFileTranscriptionWorker(
            sessionFactory,
            new PcmWaveFrameSource(),
            TimeSpan.FromSeconds(20));
        var runtimeLocator = new FfmpegRuntimeLocator(AppContext.BaseDirectory);
        var rawMediaPreparer = new FfmpegFileMediaPreparer(
            runtimeLocator,
            new FfmpegRuntimeVerifier(),
            new FfmpegProcessRunner());
        var temporaryRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoxFlow",
            "Temp");
        Directory.CreateDirectory(temporaryRoot);
        _ = new FfmpegTemporaryFileCleaner().CleanupStaleDirectories(
            temporaryRoot,
            TimeProvider.System.GetUtcNow().AddDays(-1));
        var mediaPreparer = new FfmpegFileTranscriptionMediaPreparer(
            rawMediaPreparer,
            temporaryRoot);
        fileTranscriptionPlayback = new FileTranscriptionPlaybackService(
            new FfmpegFileTranscriptionPlaybackDecoder(rawMediaPreparer, temporaryRoot),
            new WasapiFileTranscriptionPlaybackOutput());
        var deferredExecutor = new DeferredFileTranscriptionJobExecutor();
        fileTranscriptionQueue = new FileTranscriptionQueueService(deferredExecutor);
        deferredExecutor.Inner = new FileTranscriptionJobExecutor(
            fileTranscriptionJobs,
            fileTranscriptionSegments,
            new LocalFileSourceAvailabilityProbe(),
            mediaPreparer,
            worker,
            fileTranscriptionQueue,
            TimeProvider.System);
        fileTranscriptionLifecycle = new FileTranscriptionJobLifecycleService(
            fileTranscriptionJobs,
            fileTranscriptionSegments,
            fileTranscriptionQueue,
            TimeProvider.System);
        _ = fileTranscriptionLifecycle.RecoverInterruptedWork();
        fileTranscriptionCopy = new FileTranscriptionCopyService(
            new WpfTextClipboardWriter());
        fileTranscriptionExport = new FileTranscriptionExportService(
            fileTranscriptionSegments,
            new WindowsFileTranscriptionExportDestination(),
            new FileTranscriptionExportLabels(
                L10n.Localize("FileTranscriptionOriginalHeading"),
                L10n.Localize("FileTranscriptionTranslationHeading")));
        fileTranscriptionTranslation = new FileTranscriptionTranslationService(
            fileTranscriptionJobs,
            new OpenAiFileTranscriptionTranslator(
                credentialVault,
                LlmSettingsStore,
                openAiClient),
            TimeProvider.System);
        fileTranscriptionState = new FileTranscriptionStateProjection(
            fileTranscriptionJobs,
            StateStore);
        UnifiedHistory = new UnifiedHistoryQueryService(
            HistoryStore,
            WorkflowTasks,
            fileTranscriptionJobs,
            agentSessionWorkspaces,
            ScreenshotRecords);
        deferredExecutor.AfterExecute = () => fileTranscriptionState.Refresh();
        _ = fileTranscriptionState.Refresh();
    }

    public VoxFlowStateStore StateStore { get; }

    public InteractiveFeatureDependencyGate InteractiveFeatures { get; }

    public ITextProcessingSettingsStore TextSettingsStore { get; }

    public IGlossaryStore GlossaryStore { get; }

    public IGlossarySuggestionSource GlossarySuggestions { get; }

    public IWritingStyleStore WritingStyleStore { get; }

    public IHistoryReprocessor HistoryReprocessor { get; }

    public ILlmProviderSettingsStore LlmSettingsStore { get; }

    public IWorkflowTaskRepository? WorkflowTasks { get; }

    public WorkflowTaskService? WorkflowTaskService { get; }

    /// <summary>Managed Agent session storage. Only the retention boundary may
    /// clean transient OCR data or delete retained sessions.</summary>
    public AgentSessionWorkspaceRetentionService? AgentSessionWorkspaces { get; }

    public IInteractiveHotkeySettingsStore? InteractiveHotkeySettingsStore { get; }

    public InteractiveHotkeyBindingSet? InteractiveHotkeyBindings { get; private set; }

    public InteractiveHotkeyRoute? InteractiveHotkeyRoute { get; }

    public void UpdateInteractiveHotkeyBindings(
        InteractiveHotkeyBindingSet bindings)
    {
        ArgumentNullException.ThrowIfNull(bindings);
        InteractiveHotkeyBindings = bindings;
        InteractiveHotkeyRoute?.UpdateBindings(bindings);
    }

    public ValueTask ReleaseSelectedLocalModelAsync(CancellationToken cancellationToken)
    {
        var selection = ReadAsrSelection();
        return selection is { Provider: AsrProviderId.Qwen, QwenVariant: { } variant }
            ? qwenRuntime.ReleaseAsync(variant, cancellationToken)
            : ValueTask.CompletedTask;
    }

    public IHistoryStore HistoryStore { get; }

    public IUnifiedHistoryService UnifiedHistory { get; }

    public OpenAiSettingsService OpenAiSettingsService { get; }

    public ILlmProviderManagementService? LlmProviderManagement { get; }

    public SelectionTransformService? SelectionTransformService { get; }

    public ScreenshotRunRegistry ScreenshotRuns { get; }

    public IScreenshotRecordRepository ScreenshotRecords { get; }

    public IScreenshotAssetStore ScreenshotAssets { get; }

    public ScreenshotMaintenanceService ScreenshotMaintenance { get; }

    public ScreenshotMaintenanceResult ScreenshotMaintenanceResult { get; }

    public IScreenshotOcrService ScreenshotOcr { get; }

    public IScreenshotOcrEngine ScreenshotOcrEngine { get; }

    public IScreenshotCompletionService ScreenshotCompletion { get; }

    public IScreenshotAutomationSettingsStore ScreenshotAutomationSettingsStore { get; }

    public IScreenshotTransformStreamingService? ScreenshotTransforms { get; }

    public IScreenshotTransformCacheInvalidator ScreenshotTransformCacheInvalidator { get; }

    public ScreenshotTransformPersistenceCoordinator? ScreenshotTransformPersistence { get; }

    public Dx11ScreenshotFrameSource ScreenshotFrames { get; }

    public WindowsScreenshotCaptureLifecycle ScreenshotCaptureLifecycle { get; }

    public InteractiveWorkflowCoordinator ScreenshotWorkflows { get; }

    public ScreenshotSourceRenderer ScreenshotRenderer { get; }

    public IScreenshotInlineTranslationService ScreenshotInlineTranslation { get; }

    /// <summary>Real bundled sidecar entry point. It remains null whenever the
    /// feature is disabled or the manifest/hash verifier rejected the runtime.</summary>
    public IAgentComposeExecutionService? AgentComposeExecution { get; }

    /// <summary>
    /// Single readiness snapshot for the built-in Windows sidecar. Consumers
    /// must use this status rather than probing PATH or launching a fallback.
    /// </summary>
    public BuiltinAgentRuntimeStatus? BuiltinAgentRuntime { get; }

    public CloudAsrSettingsCoordinator CloudAsrSettings { get; }

    public QwenModelCatalog QwenCatalog { get; }

    public QwenModelEntryPointProjection QwenModels { get; }

    public IQwenModelOperations QwenModelOperations { get; }

    public DictationOrchestrator CreateDictationOrchestrator(
        IDictationAsrProvider provider,
        IDictationAudioCapture audio,
        IDictationOutput output,
        IDictationHistorySink history,
        IDictationProgressSink progress,
        TimeProvider timeProvider,
        TimeSpan finalTimeout,
        IDictationTextPostProcessor? processor = null,
        IDictationTargetCapture? targetCapture = null)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        return new DictationOrchestrator(
            provider,
            audio,
            processor ?? textProcessor,
            output,
            history,
            progress,
            timeProvider,
            finalTimeout,
            targetCapture);
    }

    public IDictationAsrProvider CreateSelectedDictationProvider() =>
        new ResolvingDictationAsrProvider(ResolveSelectedDictationProvider);

    /// <summary>
    /// Re-evaluates every Agent-only dependency immediately before recording.
    /// This deliberately reveals the default credential only long enough to
    /// prove that the Agent resolver can use it; no secret leaves the resolver.
    /// </summary>
    public async ValueTask<AgentComposeReadinessInput> ReadAgentComposeReadinessAsync(
        CancellationToken cancellationToken)
    {
        var runtimeAvailable = AgentComposeExecution is not null
            && new BuiltinAgentRuntimeVerifier().Verify(AppContext.BaseDirectory).IsAvailable;
        var asrAvailability = CreateSelectedDictationProvider().Availability;
        var provider = LlmProviderManagement?
            .List()
            .FirstOrDefault(candidate => candidate.IsDefault && candidate.Enabled);
        var resolvedProvider = agentProviderResolver is null
            ? null
            : await agentProviderResolver.ResolveDefaultAsync(cancellationToken)
                .ConfigureAwait(false);
        return new AgentComposeReadinessInput(
            runtimeAvailable,
            asrAvailability,
            HasDefaultProvider: resolvedProvider is not null,
            provider?.AgentCapabilityStatus ?? LlmAgentCapabilityStatus.Unknown);
    }

    public AsrSelection? ReadSelectedAsrSelection() => ReadAsrSelection();

    /// <summary>
    /// Loads cloud credential readiness, restores the durable ASR selection, and
    /// falls back to the first ready cloud provider so dictation is never left
    /// unconfigured when valid credentials already exist.
    /// </summary>
    public async Task BootstrapAsrAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        // Read this before projecting provider readiness. LoadAsync publishes a
        // ProviderSelection state change while the in-memory selection is still
        // empty, and the persistence subscriber would otherwise delete the saved
        // choice before we have a chance to restore it.
        var saved = asrSelectionStore.Load()?.ToSelection();
        var cloud = await CloudAsrSettings.LoadAsync(cancellationToken)
            .ConfigureAwait(false);

        // Qwen readiness is recorded by the Qwen projection separately; cloud
        // credentials become selectable as soon as they are complete.
        if (saved is not null && TrySelectExisting(saved))
        {
            return;
        }

        if (ReadAsrSelection() is not null)
        {
            return;
        }

        if (cloud.TencentConfigured)
        {
            asrStateCoordinator.SelectAsr(AsrProviderId.TencentCloud, null);
            return;
        }

        if (cloud.AliyunConfigured)
        {
            asrStateCoordinator.SelectAsr(AsrProviderId.AliyunDashScope, null);
            return;
        }

        if (cloud.VolcengineConfigured)
        {
            asrStateCoordinator.SelectAsr(AsrProviderId.Volcengine, null);
        }
    }

    public FileTranscriptionPageViewModel CreateFileTranscriptionPageViewModel() => new(
        L10n.Localize("FileTranscriptionHeading"),
        L10n.Localize("FileTranscriptionSubtitle"),
        fileTranscriptionJobs,
        fileTranscriptionQueue,
        ReadAsrSelection,
        ReadRecognitionLanguage,
        TimeProvider.System,
        segments: fileTranscriptionSegments,
        lifecycle: fileTranscriptionLifecycle,
        copyService: fileTranscriptionCopy,
        exportService: fileTranscriptionExport,
        translationService: fileTranscriptionTranslation,
        playbackService: fileTranscriptionPlayback,
        stateRefresh: () => fileTranscriptionState.Refresh());

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        fileTranscriptionPlayback.DisposeAsync().AsTask().GetAwaiter().GetResult();
        ScreenshotRuns.InvalidateAll();
        ScreenshotCaptureLifecycle.Shutdown();
        ScreenshotCaptureLifecycle.Dispose();
        ScreenshotFrames.Dispose();
        httpClient.Dispose();
        agentWebFetchClient?.Dispose();
        agentWebSearchClient?.Dispose();
        asrSelectionPersistence.Dispose();
        fileTranscriptionQueue.DisposeAsync().AsTask().GetAwaiter().GetResult();
        qwenRuntime.DisposeAsync().AsTask().GetAwaiter().GetResult();
        qwenReadinessHost.DisposeAsync().AsTask().GetAwaiter().GetResult();
        QwenModels.Dispose();
        credentialVault.Dispose();
        transactionRunner.Dispose();
        agentToolClipboard?.Dispose();
    }

    private void OnAsrSelectionStateChanged(StateChanged change)
    {
        if ((change.Changes & StateChangeKind.ProviderSelection) == 0)
        {
            return;
        }

        try
        {
            asrSelectionStore.Save(ReadAsrSelection());
        }
        catch
        {
            // Persistence is best-effort; selection remains valid in memory.
        }
    }

    private bool TrySelectExisting(AsrSelection selection)
    {
        try
        {
            asrStateCoordinator.SelectAsr(selection.Provider, selection.QwenVariant);
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private AsrSelection? ReadAsrSelection()
    {
        var settings = StateStore.Current.State.Settings;
        if (!settings.TryGetValue("asr.selected.provider", out var providerText)
            || !Enum.TryParse<AsrProviderId>(providerText, out var provider))
        {
            return null;
        }
        if (provider != AsrProviderId.Qwen)
        {
            return new AsrSelection(provider, null);
        }
        return settings.TryGetValue("asr.selected.variant", out var variantText)
            && Enum.TryParse<QwenVariant>(variantText, out var variant)
                ? new AsrSelection(provider, variant)
                : null;
    }

    private IDictationAsrProvider? ResolveSelectedDictationProvider()
    {
        var selection = ReadAsrSelection();
        return selection switch
        {
            { Provider: AsrProviderId.Qwen, QwenVariant: { } variant } =>
                qwenRuntime.CreateProvider(variant),
            { Provider: AsrProviderId.TencentCloud } =>
                new FactoryDictationAsrProvider(
                    AsrProviderAvailability.Ready,
                    CreateTencentSessionAsync),
            { Provider: AsrProviderId.AliyunDashScope } =>
                new FactoryDictationAsrProvider(
                    AsrProviderAvailability.Ready,
                    CreateAliyunSessionAsync),
            { Provider: AsrProviderId.Volcengine } =>
                new FactoryDictationAsrProvider(
                    AsrProviderAvailability.Ready,
                    CreateVolcengineSessionAsync),
            _ => null,
        };
    }

    private async ValueTask<IDictationAsrSession> CreateTencentSessionAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        var credentials = await tencentAsrSettings.RevealAsync(cancellationToken)
            .ConfigureAwait(false)
            ?? throw new InvalidOperationException("Tencent ASR is not configured.");
        return new TencentAsrSession(
            credentials,
            TencentAsrOptions.Default,
            generation.ToString("N"),
            new TencentSignedUrlBuilder(),
            new ClientWebSocketAdapter());
    }

    private async ValueTask<IDictationAsrSession> CreateAliyunSessionAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        _ = generation;
        var apiKey = await aliyunAsrSettings.RevealApiKeyAsync(cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("Aliyun ASR is not configured.");
        }
        return new AliyunRealtimeAsrSession(apiKey, cloudSocketFactory);
    }

    private async ValueTask<IDictationAsrSession> CreateVolcengineSessionAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        _ = generation;
        var credentials = await volcengineAsrSettings.RevealAsync(cancellationToken)
            .ConfigureAwait(false)
            ?? throw new InvalidOperationException("Volcengine ASR is not configured.");
        return new VolcengineRealtimeAsrSession(credentials, cloudSocketFactory);
    }

    private RecognitionLanguage ReadRecognitionLanguage()
    {
        var settings = StateStore.Current.State.Settings;
        return settings.TryGetValue("recognition.language", out var value)
            && Enum.TryParse<RecognitionLanguage>(value, out var language)
                ? language
                : RecognitionLanguage.Automatic;
    }

    private static ReadOnlyMemory<short> LoadReadinessCanary()
    {
        var source = new PcmWaveFrameSource();
        var frames = new List<byte>();
        var path = Path.Combine(AppContext.BaseDirectory, "Qwen", "readiness-canary.wav");
        var enumerator = source.ReadFramesAsync(path, CancellationToken.None)
            .GetAsyncEnumerator();
        try
        {
            while (enumerator.MoveNextAsync().AsTask().GetAwaiter().GetResult())
            {
                frames.AddRange(enumerator.Current.ToArray());
            }
        }
        finally
        {
            enumerator.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }

        var pcm = new short[frames.Count / sizeof(short)];
        var bytes = CollectionsMarshal.AsSpan(frames);
        for (var index = 0; index < pcm.Length; index++)
        {
            pcm[index] = BinaryPrimitives.ReadInt16LittleEndian(
                bytes.Slice(index * sizeof(short), sizeof(short)));
        }
        return pcm;
    }

    private QwenVariant SelectedQwenVariant() =>
        ReadAsrSelection() is { Provider: AsrProviderId.Qwen, QwenVariant: { } variant }
            ? variant
            : IsQwenReady(
                new SqliteModelInstallStateRepository(transactionRunner),
                QwenVariant.Qwen06B)
                ? QwenVariant.Qwen06B
                : QwenVariant.Qwen17B;

    private static bool IsQwenReady(
        IModelInstallStateRepository repository,
        QwenVariant variant)
    {
        var record = repository.LoadAsync(ModelId(variant), CancellationToken.None)
            .AsTask().GetAwaiter().GetResult();
        return record is { Phase: ModelInstallPhase.Ready, InstallPath: { Length: > 0 } path }
            && Directory.Exists(path);
    }

    private static async ValueTask<string> ResolveQwenModelPathAsync(
        IModelInstallStateRepository repository,
        QwenVariant variant,
        CancellationToken cancellationToken)
    {
        var record = await repository.LoadAsync(ModelId(variant), cancellationToken)
            .ConfigureAwait(false);
        if (record is not { Phase: ModelInstallPhase.Ready, InstallPath: { Length: > 0 } path }
            || !Directory.Exists(path))
        {
            throw new FileTranscriptionProviderUnavailableException(
                AsrProviderId.Qwen,
                FileTranscriptionErrorCode.ProviderModelNotReady);
        }
        return path;
    }

    private static string ModelId(QwenVariant variant) => variant switch
    {
        QwenVariant.Qwen06B => "qwen3-asr-0.6b",
        QwenVariant.Qwen17B => "qwen3-asr-1.7b",
        _ => throw new ArgumentOutOfRangeException(nameof(variant)),
    };

    private sealed class DeferredFileTranscriptionJobExecutor : IFileTranscriptionJobExecutor
    {
        public IFileTranscriptionJobExecutor? Inner { get; set; }
        public Action? AfterExecute { get; set; }

        public async Task ExecuteAsync(
            string jobId,
            Guid runId,
            CancellationToken cancellationToken)
        {
            try
            {
                await (Inner ?? throw new InvalidOperationException("The file executor is not initialized."))
                    .ExecuteAsync(jobId, runId, cancellationToken)
                    .ConfigureAwait(false);
            }
            finally
            {
                AfterExecute?.Invoke();
            }
        }
    }
}
