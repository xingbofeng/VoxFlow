using System.Globalization;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotSelectionPipelineTests
{
    [Fact]
    public async Task Download_writes_only_the_rendered_png_without_clipboard_ocr_history_or_result_panel()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var clipboard = new FakeClipboardGateway();
            var completion = new FakeCompletionService();
            var presenter = new FakePresenter();
            var writer = new FakeWriter();
            using var pipeline = Pipeline(
                clipboard,
                completion,
                presenter,
                new FakeDialog("C:\\Temp\\shot.png"),
                writer);

            var result = await pipeline.ProcessAsync(
                Overlay(ScreenshotCompletionKind.Download),
                Desktop(),
                CancellationToken.None);

            Assert.Equal(ScreenshotPipelineStatus.Succeeded, result.Status);
            Assert.Equal(0, clipboard.PublishCount);
            Assert.Empty(completion.Requests);
            Assert.Equal(0, presenter.PresentCount);
            Assert.Single(writer.Writes);
            Assert.Equal("C:\\Temp\\shot.png", writer.Writes[0].Path);
        });
    }

    [Fact]
    public async Task Clipboard_failure_stops_before_assets_ocr_history_and_result_panel()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var clipboard = new FakeClipboardGateway { FailPublish = true };
            var completion = new FakeCompletionService();
            var presenter = new FakePresenter();
            using var pipeline = Pipeline(
                clipboard,
                completion,
                presenter,
                new FakeDialog(null),
                new FakeWriter());

            var result = await pipeline.ProcessAsync(
                Overlay(ScreenshotCompletionKind.Complete),
                Desktop(),
                CancellationToken.None);

            Assert.Equal(ScreenshotPipelineStatus.ClipboardFailed, result.Status);
            Assert.Single(clipboard.Snapshots);
            Assert.Empty(completion.Requests);
            Assert.Equal(0, presenter.PresentCount);
        });
    }

    [Fact]
    public async Task Complete_copies_then_persists_and_presents_the_same_successful_record()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var clipboard = new FakeClipboardGateway();
            var completion = new FakeCompletionService { Succeed = true };
            var presenter = new FakePresenter();
            ScreenshotCompletionResult? published = null;
            using var pipeline = Pipeline(
                clipboard,
                completion,
                presenter,
                new FakeDialog(null),
                new FakeWriter(),
                value => published = value);

            var result = await pipeline.ProcessAsync(
                Overlay(ScreenshotCompletionKind.Complete),
                Desktop(),
                CancellationToken.None);

            Assert.Equal(ScreenshotPipelineStatus.Succeeded, result.Status);
            Assert.Equal(1, clipboard.PublishCount);
            var request = Assert.Single(completion.Requests);
            Assert.Equal(4, request.WidthPixels);
            Assert.Equal(3, request.HeightPixels);
            Assert.Equal("DISPLAY1", request.SourceDisplayId);
            Assert.Equal("Notes", request.SourceWindowTitle);
            Assert.Equal(1, presenter.PresentCount);
            Assert.Same(result.Completion, published);
            Assert.Equal(result.Completion!.ScreenshotId, presenter.LastCompletion!.ScreenshotId);
        });
    }

    [Fact]
    public async Task Inline_translation_keeps_source_ocr_searchable_and_persists_translation_separately()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            const string sourceText = "Source OCR";
            const string translatedText = "Translated output";
            var runId = Guid.NewGuid();
            var repository = new MemoryScreenshotRepository([]);
            var assetStore = new CapturingAssetStore();
            var ocr = new PathSensitiveOcrService(sourceText, translatedText);
            var completion = new ScreenshotCompletionService(
                assetStore,
                ocr,
                repository,
                new FixedRunValidity(runId));
            using var pipeline = Pipeline(
                new FakeClipboardGateway(),
                completion,
                new FakePresenter(),
                new FakeDialog(null),
                new FakeWriter());

            var result = await pipeline.ProcessAsync(
                Overlay(
                    ScreenshotCompletionKind.Complete,
                    runId,
                    [new ScreenshotInlineTranslationLine(
                        new ScreenshotPixelBounds(0, 0, 4, 3),
                        sourceText,
                        translatedText)]),
                Desktop(),
                CancellationToken.None);

            Assert.Equal(ScreenshotPipelineStatus.Succeeded, result.Status);
            Assert.Equal(CapturingAssetStore.RenderedAbsolutePath, ocr.LastRequest!.OcrImagePath);
            Assert.False(assetStore.LastRequest!.TranslatedPng.IsEmpty);
            var record = Assert.IsType<ScreenshotRecord>(result.Completion!.Record);
            Assert.Equal(sourceText, record.OcrText);
            Assert.Equal(translatedText, record.TranslatedText);
            Assert.Equal(CapturingAssetStore.TranslatedRelativePath, record.TranslatedImagePath);
            Assert.Equal(
                record.Id,
                Assert.Single(repository.Search(
                    new ScreenshotRecordQuery(sourceText, false, 0, 10)).Items).Id);
            Assert.Equal(
                record.Id,
                Assert.Single(repository.Search(
                    new ScreenshotRecordQuery(translatedText, false, 0, 10)).Items).Id);
        });
    }

    private static ScreenshotSelectionPipeline Pipeline(
        FakeClipboardGateway clipboard,
        IScreenshotCompletionService completion,
        FakePresenter presenter,
        IScreenshotSaveDialog dialog,
        IScreenshotAtomicPngWriter writer,
        Action<ScreenshotCompletionResult>? published = null) => new(
            new ScreenshotSourceRenderer(),
            new ScreenshotThumbnailEncoder(),
            new ScreenshotClipboardService(
                clipboard,
                new ScreenshotClipboardRetryPolicy(
                    maxAttempts: 1,
                    initialDelay: TimeSpan.Zero,
                    backoffFactor: 1,
                    maximumDelay: TimeSpan.Zero)),
            new ScreenshotExportService(
                dialog,
                writer,
                new ScreenshotDefaultFileNameProvider(
                    () => new DateTimeOffset(2026, 7, 14, 8, 9, 10, TimeSpan.Zero),
                    () => Guid.Empty)),
            completion,
            presenter,
            new FixedTimeProvider(),
            published);

    private static ScreenshotOverlayResult Overlay(
        ScreenshotCompletionKind kind,
        Guid? runId = null,
        IReadOnlyList<ScreenshotInlineTranslationLine>? inlineTranslationLines = null)
    {
        var image = new FrozenScreenshot(
            4,
            3,
            16,
            Enumerable.Repeat(byte.MaxValue, 48).ToArray());
        return new ScreenshotOverlayResult(
            runId ?? Guid.NewGuid(),
            kind,
            new PixelRect(0, 0, 4, 3),
            image,
            new ScreenshotDocument(Guid.NewGuid(), new PixelSize(4, 3), [], revision: 0),
            inlineTranslationLines ?? [],
            "Notes");
    }

    private static FrozenDesktop Desktop() => new(
    [
        new FrozenDisplayFrame(
            "DISPLAY1",
            "adapter",
            new CapturePixelRect(0, 0, 4, 3),
            rotationDegrees: 0,
            stride: 16,
            Enumerable.Repeat(byte.MaxValue, 48).ToArray()),
    ]);

    private sealed class FakeCompletionService : IScreenshotCompletionService
    {
        public bool Succeed { get; init; }

        public List<ScreenshotCompletionRequest> Requests { get; } = [];

        public Task<ScreenshotCompletionResult> CompleteAsync(
            ScreenshotCompletionRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Requests.Add(request);
            if (!Succeed)
            {
                return Task.FromResult(new ScreenshotCompletionResult(
                    request.RunId,
                    request.ScreenshotId,
                    ScreenshotCompletionStatus.PersistenceFailed,
                    safeErrorCode: "screenshot.persistence.record_failed"));
            }
            var record = new ScreenshotRecord(
                request.ScreenshotId,
                "Screenshots/aa/original.png",
                "Screenshots/aa/rendered.png",
                "Screenshots/aa/thumbnail.png",
                request.WidthPixels,
                request.HeightPixels,
                request.Assets.RenderedPng.Length,
                "recognized",
                request.CreatedAtUtc,
                sourceDisplayId: request.SourceDisplayId,
                sourceWindowTitle: request.SourceWindowTitle);
            return Task.FromResult(new ScreenshotCompletionResult(
                request.RunId,
                request.ScreenshotId,
                ScreenshotCompletionStatus.Succeeded,
                record));
        }
    }

    private sealed class FixedRunValidity(Guid runId) : IScreenshotRunValidity
    {
        public bool IsCurrent(Guid candidate) => candidate == runId;
    }

    private sealed class PathSensitiveOcrService(
        string sourceText,
        string translatedText) : IScreenshotOcrService
    {
        public ScreenshotOcrRequest? LastRequest { get; private set; }

        public Task<ScreenshotOcrOutcome> RecognizeAsync(
            ScreenshotOcrRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LastRequest = request;
            var text = string.Equals(
                request.OcrImagePath,
                CapturingAssetStore.RenderedAbsolutePath,
                StringComparison.OrdinalIgnoreCase)
                    ? sourceText
                    : translatedText;
            return Task.FromResult(new ScreenshotOcrOutcome(
                request.RunId,
                request.ScreenshotId,
                request.OriginalImagePath,
                ScreenshotOcrOutcomeStatus.Succeeded,
                text));
        }
    }

    private sealed class CapturingAssetStore : IScreenshotAssetStore
    {
        public const string RenderedRelativePath = "Screenshots/test/rendered.png";
        public const string TranslatedRelativePath = "Screenshots/test/translated.png";
        public const string RenderedAbsolutePath = @"C:\private\source-rendered.png";
        private const string TranslatedAbsolutePath = @"C:\private\translated-overlay.png";

        public ScreenshotAssetWriteRequest? LastRequest { get; private set; }

        public Task<ScreenshotAssetSet> SaveAsync(
            ScreenshotAssetWriteRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LastRequest = request;
            return Task.FromResult(new ScreenshotAssetSet(
                "Screenshots/test/original.png",
                RenderedRelativePath,
                "Screenshots/test/thumbnail.png",
                request.TranslatedPng.IsEmpty ? null : TranslatedRelativePath,
                request.RenderedPng.Length));
        }

        public Task<ScreenshotAssetDeleteResult> DeleteAsync(
            ScreenshotAssetSet assets,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ScreenshotAssetDeleteResult(assets.AllRelativePaths.Count));

        public string ResolveAbsolutePath(string relativePath) =>
            string.Equals(relativePath, RenderedRelativePath, StringComparison.OrdinalIgnoreCase)
                ? RenderedAbsolutePath
                : TranslatedAbsolutePath;

        public Task<int> CleanupOrphansAsync(
            IReadOnlySet<string> referencedRelativePaths,
            DateTimeOffset deleteBeforeUtcExclusive,
            CancellationToken cancellationToken) => Task.FromResult(0);
    }

    private sealed class FakePresenter : IScreenshotResultPresenter
    {
        public int PresentCount { get; private set; }

        public ScreenshotCompletionResult? LastCompletion { get; private set; }

        public bool Present(
            ScreenshotCompletionKind completionKind,
            ScreenshotCompletionResult completion)
        {
            PresentCount++;
            LastCompletion = completion;
            return true;
        }

        public void Close()
        {
        }

        public void Dispose()
        {
        }
    }

    private sealed class FakeClipboardGateway : IScreenshotClipboardGateway
    {
        public bool FailPublish { get; init; }

        public int PublishCount { get; private set; }

        public List<FakeSnapshot> Snapshots { get; } = [];

        public IScreenshotClipboardSnapshot CaptureSnapshot()
        {
            var snapshot = new FakeSnapshot();
            Snapshots.Add(snapshot);
            return snapshot;
        }

        public void Publish(ScreenshotClipboardPayload payload)
        {
            PublishCount++;
            if (FailPublish)
            {
                throw new ScreenshotClipboardException("blocked");
            }
        }

        public void Restore(IScreenshotClipboardSnapshot snapshot)
        {
        }
    }

    private sealed class FakeSnapshot : IScreenshotClipboardSnapshot
    {
        public void Dispose()
        {
        }
    }

    private sealed class FakeDialog(string? path) : IScreenshotSaveDialog
    {
        public string? Show(ScreenshotSaveDialogRequest request) => path;
    }

    private sealed class FakeWriter : IScreenshotAtomicPngWriter
    {
        public List<(string Path, int ByteCount)> Writes { get; } = [];

        public Task WriteAsync(
            string path,
            ReadOnlyMemory<byte> pngBytes,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Writes.Add((path, pngBytes.Length));
            return Task.CompletedTask;
        }
    }

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            new(2026, 7, 14, 8, 9, 10, TimeSpan.Zero);
    }
}
