using System.Globalization;
using System.IO;
using System.Text;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Domain.Screenshots;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotClipboardExportTests
{
    private static readonly CultureInfo[] SupportedCultures =
    [
        CultureInfo.InvariantCulture,
        CultureInfo.GetCultureInfo("zh-Hans"),
        CultureInfo.GetCultureInfo("zh-Hant"),
        CultureInfo.GetCultureInfo("ja"),
        CultureInfo.GetCultureInfo("ko"),
    ];

    [Fact]
    public async Task Clipboard_payload_keeps_the_renderer_png_and_exposes_browser_office_and_paint_formats()
    {
        var render = await RenderAsync();
        ScreenshotClipboardPayload? payload = null;

        await StaWpfTestHost.RunAsync(_ =>
        {
            payload = ScreenshotClipboardPayload.Create(render);
            return Task.CompletedTask;
        });

        Assert.NotNull(payload);
        Assert.Equal(render.CopyPngBytes(), payload.CopyPngBytes());
        Assert.Equal(render.Bitmap.PixelWidth, payload.Bitmap.PixelWidth);
        Assert.Equal(render.Bitmap.PixelHeight, payload.Bitmap.PixelHeight);
        Assert.True(payload.Bitmap.IsFrozen);
        Assert.Equal(
            [
                ScreenshotClipboardPayload.PngFormatName,
                ScreenshotClipboardPayload.DibV5FormatName,
                ScreenshotClipboardPayload.BitmapFormatName,
            ],
            payload.Formats);

        var dib = payload.CopyDibV5Bytes();
        Assert.Equal(124, BitConverter.ToInt32(dib, 0));
        Assert.Equal(render.Bitmap.PixelWidth, BitConverter.ToInt32(dib, 4));
        Assert.Equal(render.Bitmap.PixelHeight, BitConverter.ToInt32(dib, 8));
        Assert.Equal(32, BitConverter.ToInt16(dib, 14));
        Assert.Equal(3, BitConverter.ToInt32(dib, 16));
        Assert.Equal(unchecked((int)0x00ff0000), BitConverter.ToInt32(dib, 40));
        Assert.Equal(unchecked((int)0x0000ff00), BitConverter.ToInt32(dib, 44));
        Assert.Equal(unchecked((int)0x000000ff), BitConverter.ToInt32(dib, 48));
        Assert.Equal(unchecked((int)0xff000000), BitConverter.ToInt32(dib, 52));
        Assert.Equal(new byte[] { 10, 11, 12, 255 }, dib[124..128]);
        Assert.Equal(new byte[] { 1, 2, 3, 255 }, dib[136..140]);
    }

    [Fact]
    public async Task Clipboard_payload_is_built_off_the_ui_thread_before_publication()
    {
        var render = await RenderAsync();
        await StaWpfTestHost.RunAsync(async _ =>
        {
            var uiThreadId = Environment.CurrentManagedThreadId;
            var gateway = new FakeClipboardGateway("previous");
            var factory = new BlockingPayloadFactory();
            using var service = new ScreenshotClipboardService(
                gateway,
                ScreenshotClipboardRetryPolicy.Default,
                new CapturingClipboardDelay(),
                factory);

            var pending = service.CopyAsync(render, CultureInfo.InvariantCulture);
            try
            {
                await factory.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));

                Assert.Equal(uiThreadId, Environment.CurrentManagedThreadId);
                Assert.NotEqual(uiThreadId, factory.CreateThreadId);
                Assert.False(pending.IsCompleted);
                Assert.Equal(0, gateway.PublishCalls);
            }
            finally
            {
                factory.Release.TrySetResult();
            }

            var result = await pending.WaitAsync(TimeSpan.FromSeconds(2));
            Assert.Equal(ScreenshotClipboardWriteStatus.Copied, result.Status);
            Assert.Equal(1, gateway.PublishCalls);
        });
    }

    [Fact]
    public async Task Clipboard_busy_is_retried_with_bounded_backoff_then_reports_one_success()
    {
        var gateway = new FakeClipboardGateway("previous", busyPublishAttempts: 2);
        var delay = new CapturingClipboardDelay();
        using var service = new ScreenshotClipboardService(
            gateway,
            new ScreenshotClipboardRetryPolicy(
                maxAttempts: 3,
                initialDelay: TimeSpan.FromMilliseconds(20),
                backoffFactor: 2,
                maximumDelay: TimeSpan.FromMilliseconds(100)),
            delay);

        var result = await service.CopyAsync(await RenderAsync(), CultureInfo.InvariantCulture);

        Assert.Equal(ScreenshotClipboardWriteStatus.Copied, result.Status);
        Assert.Null(result.ErrorMessage);
        Assert.Equal(3, gateway.PublishCalls);
        Assert.Equal([TimeSpan.FromMilliseconds(20), TimeSpan.FromMilliseconds(40)], delay.Delays);
        Assert.Equal(0, gateway.RestoreCalls);
        Assert.Equal("image", gateway.CurrentValue);
    }

    [Fact]
    public async Task Clipboard_terminal_failure_restores_previous_data_and_returns_a_retryable_localized_error()
    {
        var gateway = new FakeClipboardGateway(
            "previous",
            busyPublishAttempts: int.MaxValue,
            mutateBeforeFailure: true);
        var delay = new CapturingClipboardDelay();
        using var service = new ScreenshotClipboardService(
            gateway,
            new ScreenshotClipboardRetryPolicy(
                maxAttempts: 3,
                initialDelay: TimeSpan.FromMilliseconds(1),
                backoffFactor: 1,
                maximumDelay: TimeSpan.FromMilliseconds(1)),
            delay);

        var result = await service.CopyAsync(
            await RenderAsync(),
            CultureInfo.GetCultureInfo("zh-Hans"));

        Assert.Equal(ScreenshotClipboardWriteStatus.Busy, result.Status);
        Assert.Equal("剪贴板正忙，截图未复制。请重试。", result.ErrorMessage);
        Assert.Equal(3, gateway.PublishCalls);
        Assert.Equal(1, gateway.RestoreCalls);
        Assert.Equal("previous", gateway.CurrentValue);
    }

    [Fact]
    public async Task Clipboard_non_busy_failure_does_not_retry_and_preserves_previous_data()
    {
        var gateway = new FakeClipboardGateway(
            "previous",
            publishFailure: new ScreenshotClipboardException("private diagnostic"),
            mutateBeforeFailure: true);
        var delay = new CapturingClipboardDelay();
        using var service = new ScreenshotClipboardService(
            gateway,
            ScreenshotClipboardRetryPolicy.Default,
            delay);

        var result = await service.CopyAsync(
            await RenderAsync(),
            CultureInfo.InvariantCulture);

        Assert.Equal(ScreenshotClipboardWriteStatus.Failed, result.Status);
        Assert.Equal("Couldn't copy the screenshot. Try again.", result.ErrorMessage);
        Assert.DoesNotContain("diagnostic", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(1, gateway.PublishCalls);
        Assert.Equal(1, gateway.RestoreCalls);
        Assert.Empty(delay.Delays);
        Assert.Equal("previous", gateway.CurrentValue);
    }

    [Fact]
    public async Task Result_clipboard_accepts_a_non_sta_caller_and_reuses_the_reliable_saved_image_boundary()
    {
        var render = await RenderAsync();
        var path = Path.Combine(
            Path.GetTempPath(),
            $"VoxFlow-result-clipboard-{Guid.NewGuid():N}.png");
        await File.WriteAllBytesAsync(path, render.CopyPngBytes());
        try
        {
            var gateway = new FakeClipboardGateway("previous", busyPublishAttempts: 1);
            var delay = new CapturingClipboardDelay();
            using var service = new ScreenshotClipboardService(
                gateway,
                new ScreenshotClipboardRetryPolicy(
                    maxAttempts: 2,
                    initialDelay: TimeSpan.FromMilliseconds(5),
                    backoffFactor: 1,
                    maximumDelay: TimeSpan.FromMilliseconds(5)),
                delay);
            var clipboard = new WpfScreenshotResultClipboard(service);
            var callerApartment = ApartmentState.Unknown;

            var copied = await Task.Run(async () =>
            {
                callerApartment = Thread.CurrentThread.GetApartmentState();
                return await clipboard.TrySetImageAsync(path);
            });

            Assert.True(copied);
            Assert.NotEqual(ApartmentState.STA, callerApartment);
            Assert.Equal(2, gateway.PublishCalls);
            Assert.Equal([TimeSpan.FromMilliseconds(5)], delay.Delays);
            AssertSavedImagePayload(gateway.LastPayload, render);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task Media_clipboard_reuses_the_reliable_saved_image_formats_and_busy_retry()
    {
        var render = await RenderAsync();
        var path = Path.Combine(
            Path.GetTempPath(),
            $"VoxFlow-media-clipboard-{Guid.NewGuid():N}.png");
        await File.WriteAllBytesAsync(path, render.CopyPngBytes());
        try
        {
            var gateway = new FakeClipboardGateway("previous", busyPublishAttempts: 1);
            var delay = new CapturingClipboardDelay();
            using var service = new ScreenshotClipboardService(
                gateway,
                new ScreenshotClipboardRetryPolicy(
                    maxAttempts: 2,
                    initialDelay: TimeSpan.FromMilliseconds(7),
                    backoffFactor: 1,
                    maximumDelay: TimeSpan.FromMilliseconds(7)),
                delay);
            var platform = new WpfScreenshotMediaPlatform(service);

            await platform.CopyImageAsync(path, CancellationToken.None);

            Assert.Equal(2, gateway.PublishCalls);
            Assert.Equal([TimeSpan.FromMilliseconds(7)], delay.Delays);
            AssertSavedImagePayload(gateway.LastPayload, render);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Conflict_safe_default_png_name_is_localized_for_all_five_languages()
    {
        var provider = new ScreenshotDefaultFileNameProvider(
            () => new DateTimeOffset(2026, 7, 14, 8, 9, 10, TimeSpan.FromHours(8)),
            () => Guid.Parse("01234567-89ab-cdef-0123-456789abcdef"));
        var expectedPrefixes = new[]
        {
            "VoxFlow-Screenshot",
            "VoxFlow截图",
            "VoxFlow截圖",
            "VoxFlowスクリーンショット",
            "VoxFlow스크린샷",
        };

        for (var index = 0; index < SupportedCultures.Length; index++)
        {
            var name = provider.Create(SupportedCultures[index]);

            Assert.Equal(
                $"{expectedPrefixes[index]}-20260714-080910-01234567.png",
                name);
            Assert.Equal(-1, name.IndexOfAny(Path.GetInvalidFileNameChars()));
        }
    }

    [Fact]
    public void Default_png_names_remain_unique_within_the_same_second()
    {
        var ids = new Queue<Guid>(
        [
            Guid.Parse("11111111-0000-0000-0000-000000000000"),
            Guid.Parse("22222222-0000-0000-0000-000000000000"),
        ]);
        var provider = new ScreenshotDefaultFileNameProvider(
            () => new DateTimeOffset(2026, 7, 14, 8, 9, 10, TimeSpan.FromHours(8)),
            ids.Dequeue);

        var first = provider.Create(CultureInfo.InvariantCulture);
        var second = provider.Create(CultureInfo.InvariantCulture);

        Assert.NotEqual(first, second);
        Assert.EndsWith("-11111111.png", first, StringComparison.Ordinal);
        Assert.EndsWith("-22222222.png", second, StringComparison.Ordinal);
    }

    [Fact]
    public void Save_title_filter_and_retryable_errors_are_real_resources_in_all_five_languages()
    {
        string[] keys =
        [
            "ScreenshotSaveDialogTitle",
            "ScreenshotPngFileFilter",
            "ScreenshotDefaultFileNamePrefix",
            "ScreenshotClipboardBusy",
            "ScreenshotClipboardFailed",
            "ScreenshotSaveFailed",
        ];
        foreach (var culture in SupportedCultures)
        {
            foreach (var key in keys)
            {
                var value = L10n.Localize(key, culture);
                Assert.False(string.IsNullOrWhiteSpace(value));
                Assert.NotEqual(key, value);
            }
        }
    }

    [Fact]
    public async Task Download_only_writes_the_selected_png_and_has_no_history_or_ocr_dependency()
    {
        var render = await RenderAsync();
        var selectedPath = Path.Combine(Path.GetTempPath(), "chosen-screenshot.png");
        var dialog = new CapturingSaveDialog(selectedPath);
        var writer = new CapturingAtomicPngWriter();
        var names = new FixedFileNameProvider("VoxFlow-Screenshot-safe.png");
        var service = new ScreenshotExportService(dialog, writer, names);

        var result = await service.DownloadAsync(render, CultureInfo.InvariantCulture);

        Assert.Equal(ScreenshotExportStatus.Saved, result.Status);
        Assert.Equal(selectedPath, result.Path);
        Assert.Null(result.ErrorMessage);
        Assert.Equal(selectedPath, writer.Path);
        Assert.Equal(render.CopyPngBytes(), writer.Bytes);
        Assert.NotNull(dialog.Request);
        Assert.Equal("Save screenshot", dialog.Request.Title);
        Assert.Equal("PNG image (*.png)|*.png", dialog.Request.Filter);
        Assert.Equal(".png", dialog.Request.DefaultExtension);
        Assert.Equal("VoxFlow-Screenshot-safe.png", dialog.Request.DefaultFileName);
        Assert.True(dialog.Request.AddExtension);
        Assert.True(dialog.Request.OverwritePrompt);

        var dependencyTypes = typeof(ScreenshotExportService)
            .GetConstructors()
            .SelectMany(constructor => constructor.GetParameters())
            .Select(parameter => parameter.ParameterType.FullName ?? parameter.ParameterType.Name)
            .ToArray();
        Assert.DoesNotContain(
            dependencyTypes,
            dependency => dependency.Contains("Repository", StringComparison.Ordinal)
                || dependency.Contains("Ocr", StringComparison.Ordinal)
                || dependency.Contains("Completion", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Cancelling_the_save_dialog_writes_nothing_and_keeps_a_non_error_result()
    {
        var writer = new CapturingAtomicPngWriter();
        var service = new ScreenshotExportService(
            new CapturingSaveDialog(path: null),
            writer,
            new FixedFileNameProvider("safe.png"));

        var result = await service.DownloadAsync(await RenderAsync(), CultureInfo.InvariantCulture);

        Assert.Equal(ScreenshotExportStatus.Cancelled, result.Status);
        Assert.Null(result.Path);
        Assert.Null(result.ErrorMessage);
        Assert.Equal(0, writer.WriteCalls);
    }

    [Fact]
    public async Task Save_error_returns_localized_safe_feedback_and_does_not_claim_success()
    {
        var path = Path.Combine(Path.GetTempPath(), "private", "capture.png");
        var service = new ScreenshotExportService(
            new CapturingSaveDialog(path),
            new CapturingAtomicPngWriter(new IOException("secret path details")),
            new FixedFileNameProvider("safe.png"));

        var result = await service.DownloadAsync(
            await RenderAsync(),
            CultureInfo.GetCultureInfo("ja"));

        Assert.Equal(ScreenshotExportStatus.Failed, result.Status);
        Assert.Null(result.Path);
        Assert.Equal("スクリーンショットを保存できませんでした。別の場所を選んで、もう一度お試しください。", result.ErrorMessage);
        Assert.DoesNotContain("private", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Atomic_writer_flushes_a_same_directory_temporary_file_before_replacing_the_target()
    {
        var fileSystem = new RecordingExportFileSystem(targetExists: true);
        var writer = new AtomicScreenshotPngWriter(
            fileSystem,
            () => Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"));
        var target = Path.Combine("C:\\captures", "shot.png");
        var bytes = Encoding.ASCII.GetBytes("new-png");

        await writer.WriteAsync(target, bytes, CancellationToken.None);

        Assert.Equal(["write-flush", "exists", "replace"], fileSystem.Events);
        Assert.Equal(target, fileSystem.FinalPath);
        Assert.Equal(bytes, fileSystem.Bytes);
        Assert.Contains("aaaaaaaa", fileSystem.TemporaryPath, StringComparison.Ordinal);
        Assert.Equal(
            Path.GetDirectoryName(Path.GetFullPath(target)),
            Path.GetDirectoryName(fileSystem.TemporaryPath));
        Assert.False(fileSystem.HasTemporaryFile);
    }

    [Fact]
    public async Task Atomic_writer_moves_a_new_target_and_cleans_the_temporary_file_after_failure_or_cancellation()
    {
        var newTargetFileSystem = new RecordingExportFileSystem(targetExists: false);
        var writer = new AtomicScreenshotPngWriter(newTargetFileSystem, Guid.NewGuid);

        await writer.WriteAsync(
            Path.Combine("C:\\captures", "new.png"),
            Encoding.ASCII.GetBytes("png"),
            CancellationToken.None);

        Assert.Equal(["write-flush", "exists", "move"], newTargetFileSystem.Events);
        Assert.False(newTargetFileSystem.HasTemporaryFile);

        var failingFileSystem = new RecordingExportFileSystem(
            targetExists: true,
            failure: new IOException("disk full"));
        writer = new AtomicScreenshotPngWriter(failingFileSystem, Guid.NewGuid);
        await Assert.ThrowsAsync<IOException>(() => writer.WriteAsync(
            Path.Combine("C:\\captures", "failed.png"),
            Encoding.ASCII.GetBytes("png"),
            CancellationToken.None));
        Assert.Equal(["write-flush", "exists", "replace", "delete"], failingFileSystem.Events);
        Assert.False(failingFileSystem.HasTemporaryFile);

        var cancelledFileSystem = new RecordingExportFileSystem(
            targetExists: false,
            failure: new OperationCanceledException());
        writer = new AtomicScreenshotPngWriter(cancelledFileSystem, Guid.NewGuid);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => writer.WriteAsync(
            Path.Combine("C:\\captures", "cancelled.png"),
            Encoding.ASCII.GetBytes("png"),
            CancellationToken.None));
        Assert.Contains("delete", cancelledFileSystem.Events);
        Assert.False(cancelledFileSystem.HasTemporaryFile);
    }

    [Fact]
    public async Task Physical_atomic_writer_round_trips_png_bytes_and_leaves_no_temporary_file()
    {
        var directory = Path.Combine(
            Path.GetTempPath(),
            "VoxFlow-ScreenshotExportTests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var target = Path.Combine(directory, "capture.png");
            await File.WriteAllBytesAsync(target, Encoding.ASCII.GetBytes("old"));
            var expected = Encoding.ASCII.GetBytes("replacement-png");

            await new AtomicScreenshotPngWriter().WriteAsync(
                target,
                expected,
                CancellationToken.None);

            Assert.Equal(expected, await File.ReadAllBytesAsync(target));
            Assert.Empty(Directory.EnumerateFiles(directory, "*.tmp"));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    private static async Task<ScreenshotRenderResult> RenderAsync()
    {
        ScreenshotRenderResult? result = null;
        await StaWpfTestHost.RunAsync(_ =>
        {
            const int width = 3;
            const int height = 2;
            const int stride = width * 4;
            var bgra = new byte[]
            {
                1, 2, 3, 255, 4, 5, 6, 255, 7, 8, 9, 255,
                10, 11, 12, 255, 13, 14, 15, 255, 16, 17, 18, 255,
            };
            var source = new FrozenScreenshot(width, height, stride, bgra);
            var document = new ScreenshotDocument(
                Guid.NewGuid(),
                new PixelSize(width, height),
                [],
                revision: 0);
            result = new ScreenshotSourceRenderer().Render(source, document);
            return Task.CompletedTask;
        });
        return result!;
    }

    private static void AssertSavedImagePayload(
        ScreenshotClipboardPayload? payload,
        ScreenshotRenderResult render)
    {
        Assert.NotNull(payload);
        Assert.Equal(
            [
                ScreenshotClipboardPayload.PngFormatName,
                ScreenshotClipboardPayload.DibV5FormatName,
                ScreenshotClipboardPayload.BitmapFormatName,
            ],
            payload.Formats);
        Assert.Equal(render.Bitmap.PixelWidth, payload.Bitmap.PixelWidth);
        Assert.Equal(render.Bitmap.PixelHeight, payload.Bitmap.PixelHeight);
        Assert.True(payload.Bitmap.IsFrozen);
        Assert.Equal(
            new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 },
            payload.CopyPngBytes()[..8]);
        Assert.Equal(124, BitConverter.ToInt32(payload.CopyDibV5Bytes(), 0));
    }

    private sealed class FakeClipboardSnapshot(string value) : IScreenshotClipboardSnapshot
    {
        public string Value { get; } = value;

        public void Dispose()
        {
        }
    }

    private sealed class FakeClipboardGateway(
        string initialValue,
        int busyPublishAttempts = 0,
        Exception? publishFailure = null,
        bool mutateBeforeFailure = false) : IScreenshotClipboardGateway
    {
        public int PublishCalls { get; private set; }

        public int RestoreCalls { get; private set; }

        public string CurrentValue { get; private set; } = initialValue;

        public ScreenshotClipboardPayload? LastPayload { get; private set; }

        public IScreenshotClipboardSnapshot CaptureSnapshot() =>
            new FakeClipboardSnapshot(CurrentValue);

        public void Publish(ScreenshotClipboardPayload payload)
        {
            ArgumentNullException.ThrowIfNull(payload);
            PublishCalls++;
            if (mutateBeforeFailure)
            {
                CurrentValue = "partial-image";
            }

            if (PublishCalls <= busyPublishAttempts)
            {
                throw new ScreenshotClipboardBusyException("busy");
            }

            if (publishFailure is not null)
            {
                throw publishFailure;
            }

            LastPayload = payload;
            CurrentValue = "image";
        }

        public void Restore(IScreenshotClipboardSnapshot snapshot)
        {
            RestoreCalls++;
            CurrentValue = Assert.IsType<FakeClipboardSnapshot>(snapshot).Value;
        }
    }

    private sealed class CapturingClipboardDelay : IScreenshotClipboardRetryDelay
    {
        public List<TimeSpan> Delays { get; } = [];

        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Delays.Add(delay);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class BlockingPayloadFactory : IScreenshotClipboardPayloadFactory
    {
        public TaskCompletionSource Started { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource Release { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public int CreateThreadId { get; private set; }

        public ScreenshotClipboardPayload Create(ScreenshotRenderResult render)
        {
            CreateThreadId = Environment.CurrentManagedThreadId;
            Started.TrySetResult();
            Release.Task.GetAwaiter().GetResult();
            return ScreenshotClipboardPayload.Create(render);
        }

        public ScreenshotClipboardPayload CreateFromImageFile(string absoluteImagePath) =>
            ScreenshotClipboardPayload.CreateFromImageFile(absoluteImagePath);
    }

    private sealed class CapturingSaveDialog(string? path) : IScreenshotSaveDialog
    {
        public ScreenshotSaveDialogRequest? Request { get; private set; }

        public string? Show(ScreenshotSaveDialogRequest request)
        {
            Request = request;
            return path;
        }
    }

    private sealed class CapturingAtomicPngWriter(Exception? failure = null)
        : IScreenshotAtomicPngWriter
    {
        public int WriteCalls { get; private set; }

        public string? Path { get; private set; }

        public byte[]? Bytes { get; private set; }

        public Task WriteAsync(
            string path,
            ReadOnlyMemory<byte> pngBytes,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            WriteCalls++;
            Path = path;
            Bytes = pngBytes.ToArray();
            return failure is null ? Task.CompletedTask : Task.FromException(failure);
        }
    }

    private sealed class FixedFileNameProvider(string name)
        : IScreenshotDefaultFileNameProvider
    {
        public string Create(CultureInfo culture) => name;
    }

    private sealed class RecordingExportFileSystem(
        bool targetExists,
        Exception? failure = null) : IScreenshotExportFileSystem
    {
        private readonly bool targetExists = targetExists;
        private readonly Exception? failure = failure;

        public List<string> Events { get; } = [];

        public string TemporaryPath { get; private set; } = string.Empty;

        public string FinalPath { get; private set; } = string.Empty;

        public byte[]? Bytes { get; private set; }

        public bool HasTemporaryFile { get; private set; }

        public Task WriteAndFlushAsync(
            string path,
            ReadOnlyMemory<byte> bytes,
            CancellationToken cancellationToken)
        {
            Events.Add("write-flush");
            TemporaryPath = path;
            Bytes = bytes.ToArray();
            HasTemporaryFile = true;
            return Task.CompletedTask;
        }

        public bool FileExists(string path)
        {
            Events.Add("exists");
            return targetExists;
        }

        public void Replace(string sourcePath, string destinationPath)
        {
            Events.Add("replace");
            if (failure is not null)
            {
                throw failure;
            }

            FinalPath = destinationPath;
            HasTemporaryFile = false;
        }

        public void Move(string sourcePath, string destinationPath)
        {
            Events.Add("move");
            if (failure is not null)
            {
                throw failure;
            }

            FinalPath = destinationPath;
            HasTemporaryFile = false;
        }

        public void DeleteIfExists(string path)
        {
            Events.Add("delete");
            HasTemporaryFile = false;
        }
    }
}
