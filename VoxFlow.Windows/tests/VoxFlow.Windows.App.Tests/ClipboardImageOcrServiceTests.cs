using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ClipboardImageOcrServiceTests
{
    [Fact]
    public async Task Hotkey_with_clipboard_image_completes_ocr_and_presents_result()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var png = CreateSolidPng(48, 32);
            var completion = new CapturingCompletionService("hello from ocr");
            var presenter = new CapturingResultPresenter();
            var failures = new List<string>();
            using var service = CreateService(
                completion,
                presenter,
                isEnabled: () => true,
                readPng: (out byte[] bytes, out int width, out int height) =>
                {
                    bytes = png;
                    width = 48;
                    height = 32;
                    return true;
                },
                reportFailure: (code, _) => failures.Add(code));

            var result = await service.RunFromHotkeyAsync(CancellationToken.None);

            Assert.Equal(ClipboardImageOcrStatus.Succeeded, result.Status);
            Assert.NotNull(result.Completion);
            Assert.Equal(1, completion.CallCount);
            Assert.Equal(1, presenter.PresentCount);
            Assert.Equal(
                ScreenshotCompletionKind.TextRecognition,
                presenter.LastKind);
            Assert.Empty(failures);
            Assert.Equal("hello from ocr", result.Completion!.Record!.OcrText);
        });
    }

    [Fact]
    public async Task Hotkey_without_image_reports_no_image_and_does_not_present()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var completion = new CapturingCompletionService("unused");
            var presenter = new CapturingResultPresenter();
            var failures = new List<string>();
            using var service = CreateService(
                completion,
                presenter,
                isEnabled: () => true,
                readPng: (out byte[] bytes, out int width, out int height) =>
                {
                    bytes = [];
                    width = 0;
                    height = 0;
                    return false;
                },
                reportFailure: (code, _) => failures.Add(code));

            var result = await service.RunFromHotkeyAsync(CancellationToken.None);

            Assert.Equal(ClipboardImageOcrStatus.NoImage, result.Status);
            Assert.Equal(0, completion.CallCount);
            Assert.Equal(0, presenter.PresentCount);
            Assert.Contains("clipboard.ocr.no_image", failures);
        });
    }

    [Fact]
    public async Task Auto_watch_skips_when_disabled_without_reading_clipboard()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var readCalls = 0;
            var completion = new CapturingCompletionService("unused");
            var presenter = new CapturingResultPresenter();
            using var service = CreateService(
                completion,
                presenter,
                isEnabled: () => false,
                readPng: (out byte[] bytes, out int width, out int height) =>
                {
                    readCalls++;
                    bytes = CreateSolidPng(16, 16);
                    width = 16;
                    height = 16;
                    return true;
                });

            var result = await service.RunFromClipboardChangeAsync(CancellationToken.None);

            Assert.Equal(ClipboardImageOcrStatus.Disabled, result.Status);
            Assert.Equal(0, readCalls);
            Assert.Equal(0, completion.CallCount);
            Assert.Equal(0, presenter.PresentCount);
        });
    }

    [Fact]
    public async Task Auto_watch_runs_when_enabled_and_image_is_available()
    {
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var png = CreateSolidPng(20, 20);
            var completion = new CapturingCompletionService("auto ocr");
            var presenter = new CapturingResultPresenter();
            using var service = CreateService(
                completion,
                presenter,
                isEnabled: () => true,
                readPng: (out byte[] bytes, out int width, out int height) =>
                {
                    bytes = png;
                    width = 20;
                    height = 20;
                    return true;
                },
                readSequence: () => 42u);

            var result = await service.RunFromClipboardChangeAsync(CancellationToken.None);

            Assert.Equal(ClipboardImageOcrStatus.Succeeded, result.Status);
            Assert.Equal(1, completion.CallCount);
            Assert.Equal(1, presenter.PresentCount);
        });
    }

    [Fact]
    public async Task Automation_settings_toggle_persists_and_notifies_callback()
    {
        var store = new InMemoryScreenshotAutomationSettingsStore();
        var notified = new List<bool>();
        var hotkeys = new InteractiveHotkeySettingsViewModel(
            new MemoryInteractiveHotkeySettingsStoreForClipboard());
        await hotkeys.InitializeAsync(CancellationToken.None);
        var page = new ScreenshotSettingsPageViewModel(
            hotkeys,
            store,
            enabled => notified.Add(enabled));
        await page.LoadAsync(CancellationToken.None);

        Assert.True(page.ClipboardOcrEnabled);
        page.ClipboardOcrEnabled = false;
        // Allow fire-and-forget save to complete.
        await Task.Delay(50);

        var reloaded = await store.LoadAsync(CancellationToken.None);
        Assert.False(reloaded.ClipboardImageOcrEnabled);
        Assert.Contains(false, notified);
    }

    private static ClipboardImageOcrService CreateService(
        IScreenshotCompletionService completion,
        IScreenshotResultPresenter presenter,
        Func<bool> isEnabled,
        ClipboardImagePngReader readPng,
        Action<string, Exception?>? reportFailure = null,
        Func<uint>? readSequence = null) =>
        new(
            Dispatcher.CurrentDispatcher,
            completion,
            presenter,
            new ScreenshotRunRegistry(),
            new InteractiveWorkflowCoordinator(),
            isEnabled,
            isVoiceWorkflowActive: () => false,
            completionPublished: null,
            reportFailure: reportFailure,
            thumbnails: new ScreenshotThumbnailEncoder(),
            readClipboardPng: readPng,
            readClipboardSequence: readSequence ?? (() => 1u));

    private static byte[] CreateSolidPng(int width, int height)
    {
        var bitmap = new WriteableBitmap(
            width,
            height,
            96,
            96,
            PixelFormats.Bgra32,
            null);
        var stride = width * 4;
        var pixels = new byte[stride * height];
        for (var i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] = 0x20;
            pixels[i + 1] = 0x40;
            pixels[i + 2] = 0x80;
            pixels[i + 3] = 0xFF;
        }
        bitmap.WritePixels(
            new System.Windows.Int32Rect(0, 0, width, height),
            pixels,
            stride,
            0);
        bitmap.Freeze();
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private sealed class CapturingCompletionService(string ocrTextResult) : IScreenshotCompletionService
    {
        public int CallCount { get; private set; }

        public Task<ScreenshotCompletionResult> CompleteAsync(
            ScreenshotCompletionRequest request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            var ocrText = ocrTextResult;
            if (request.Assets.OriginalPng.Length == 0)
            {
                return Task.FromResult(new ScreenshotCompletionResult(
                    request.RunId,
                    request.ScreenshotId,
                    ScreenshotCompletionStatus.AssetFailed,
                    safeErrorCode: "screenshot.persistence.asset_failed"));
            }

            var record = new ScreenshotRecord(
                request.ScreenshotId,
                $"Screenshots/{request.ScreenshotId}/original.png",
                $"Screenshots/{request.ScreenshotId}/rendered.png",
                $"Screenshots/{request.ScreenshotId}/thumbnail.png",
                request.WidthPixels,
                request.HeightPixels,
                request.Assets.OriginalPng.Length,
                ocrText,
                request.CreatedAtUtc,
                sourceWindowTitle: request.SourceWindowTitle);
            var ocr = string.IsNullOrWhiteSpace(ocrText)
                ? new ScreenshotOcrOutcome(
                    request.RunId,
                    request.ScreenshotId,
                    record.OriginalImagePath,
                    ScreenshotOcrOutcomeStatus.Empty)
                : new ScreenshotOcrOutcome(
                    request.RunId,
                    request.ScreenshotId,
                    record.OriginalImagePath,
                    ScreenshotOcrOutcomeStatus.Succeeded,
                    ocrText,
                    [new ScreenshotOcrLine(
                        ocrText,
                        90,
                        new ScreenshotPixelBounds(0, 0, request.WidthPixels, request.HeightPixels))]);
            return Task.FromResult(new ScreenshotCompletionResult(
                request.RunId,
                request.ScreenshotId,
                ScreenshotCompletionStatus.Succeeded,
                record,
                ocr));
        }
    }

    private sealed class CapturingResultPresenter : IScreenshotResultPresenter
    {
        public int PresentCount { get; private set; }

        public ScreenshotCompletionKind? LastKind { get; private set; }

        public bool Present(
            ScreenshotCompletionKind completionKind,
            ScreenshotCompletionResult completion)
        {
            PresentCount++;
            LastKind = completionKind;
            return true;
        }

        public void Close()
        {
        }

        public void Dispose()
        {
        }
    }

    private sealed class InMemoryScreenshotAutomationSettingsStore
        : IScreenshotAutomationSettingsStore
    {
        private ScreenshotAutomationSettings settings = ScreenshotAutomationSettings.Default;

        public ValueTask<ScreenshotAutomationSettings> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(settings);

        public ValueTask SaveAsync(
            ScreenshotAutomationSettings value,
            CancellationToken cancellationToken)
        {
            settings = value;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class MemoryInteractiveHotkeySettingsStoreForClipboard
        : IInteractiveHotkeySettingsStore
    {
        public InteractiveHotkeySettingsDocument Current { get; private set; } =
            InteractiveHotkeySettingsDocument.Default;

        public ValueTask<InteractiveHotkeySettingsDocument> LoadAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult(Current);

        public ValueTask SaveAsync(
            InteractiveHotkeySettingsDocument settings,
            CancellationToken cancellationToken)
        {
            Current = settings;
            return ValueTask.CompletedTask;
        }
    }
}
