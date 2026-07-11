using System.Net.Http;
using System.IO;
using VoxFlow.Windows.App.State;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Security;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Infrastructure.Media;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Files;
using VoxFlow.Windows.Platform.Audio;
using VoxFlow.Windows.Providers.Cloud.OpenAI;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;
using VoxFlow.Windows.Providers.Qwen;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Home;
using VoxFlow.Windows.App.Localization;

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
    private int disposed;

    public WindowsAppCompositionRoot(
        string databasePath,
        IStreamingTextRefiner? textRefiner = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(databasePath);
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        var connectionFactory = new SqliteConnectionFactory(databasePath, pooling: false);
        transactionRunner = new SqliteTransactionRunner(connectionFactory);
        credentialVault = new SqliteCredentialVault(
            connectionFactory,
            new DpapiCurrentUserDataProtector());
        httpClient = new HttpClient
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };

        TextSettingsStore = new SqliteTextProcessingSettingsStore(transactionRunner);
        LlmSettingsStore = new SqliteLlmProviderSettingsStore(transactionRunner);
        HistoryStore = new SqliteHistoryStore(transactionRunner);
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
        var tencentSettings = new TencentAsrSettingsService(
            credentialVault,
            new TencentSettingsConnectionTester());
        var aliyunSettings = new AliyunAsrSettingsService(
            credentialVault,
            new AliyunSettingsConnectionTester());
        var volcengineSettings = new VolcengineAsrSettingsService(credentialVault);
        CloudAsrSettings = new CloudAsrSettingsCoordinator(
            tencentSettings,
            aliyunSettings,
            volcengineSettings,
            new SettingsStateCoordinator(StateStore));
        textRefiner ??= new OpenAiStreamingTextRefiner(
            credentialVault,
            LlmSettingsStore,
            openAiClient);
        textProcessor = new ConfigurableTextProcessingPipeline(
            TextSettingsStore,
            new ConservativeLlmTextPostProcessor(textRefiner));

        fileTranscriptionJobs = new SqliteFileTranscriptionJobRepository(transactionRunner);
        fileTranscriptionSegments = new SqliteFileTranscriptionSegmentRepository(transactionRunner);
        qwenRuntime = new QwenDictationProviderRuntime(
            variant => IsQwenReady(modelRepository, variant),
            (variant, cancellationToken) => ResolveQwenModelPathAsync(
                modelRepository,
                variant,
                cancellationToken));
        var socketFactory = new ClientWebSocketFactory();
        var sessionFactory = new FileTranscriptionSessionFactory(
        [
            new QwenFileTranscriptionSessionAdapter(_ =>
                qwenRuntime.CreateProvider(SelectedQwenVariant())),
            new TencentFileTranscriptionSessionAdapter(tencentSettings, socketFactory),
            new AliyunFileTranscriptionSessionAdapter(aliyunSettings, socketFactory),
            new VolcengineFileTranscriptionSessionAdapter(volcengineSettings, socketFactory),
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
        deferredExecutor.AfterExecute = () => fileTranscriptionState.Refresh();
        _ = fileTranscriptionState.Refresh();
    }

    public VoxFlowStateStore StateStore { get; }

    public ITextProcessingSettingsStore TextSettingsStore { get; }

    public ILlmProviderSettingsStore LlmSettingsStore { get; }

    public IHistoryStore HistoryStore { get; }

    public OpenAiSettingsService OpenAiSettingsService { get; }

    public CloudAsrSettingsCoordinator CloudAsrSettings { get; }

    public QwenModelCatalog QwenCatalog { get; }

    public QwenModelEntryPointProjection QwenModels { get; }

    public DictationOrchestrator CreateDictationOrchestrator(
        IDictationAsrProvider provider,
        IDictationAudioCapture audio,
        IDictationOutput output,
        IDictationHistorySink history,
        IDictationProgressSink progress,
        TimeProvider timeProvider,
        TimeSpan finalTimeout)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        return new DictationOrchestrator(
            provider,
            audio,
            textProcessor,
            output,
            history,
            progress,
            timeProvider,
            finalTimeout);
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
        httpClient.Dispose();
        fileTranscriptionQueue.DisposeAsync().AsTask().GetAwaiter().GetResult();
        qwenRuntime.DisposeAsync().AsTask().GetAwaiter().GetResult();
        QwenModels.Dispose();
        credentialVault.Dispose();
        transactionRunner.Dispose();
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

    private RecognitionLanguage ReadRecognitionLanguage()
    {
        var settings = StateStore.Current.State.Settings;
        return settings.TryGetValue("recognition.language", out var value)
            && Enum.TryParse<RecognitionLanguage>(value, out var language)
                ? language
                : RecognitionLanguage.Automatic;
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
