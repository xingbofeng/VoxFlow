using Windows.Graphics.Imaging;
using Windows.Storage;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class TesseractScreenshotOcrAdapterTests
{
    [Fact]
    public void Screenshot_process_adds_tsv_without_changing_plain_text_argument_shape()
    {
        var plain = Request(TesseractOcrOutputFormat.PlainText);
        var tsv = Request(TesseractOcrOutputFormat.Tsv);

        Assert.Equal(
            new[]
            {
                plain.ScreenshotPath, "stdout", "-l", "chi_sim+eng",
                "--tessdata-dir", plain.TessdataPath, "--psm", "3",
            },
            TesseractOcrProcessRunner.CreateStartInfo(plain).ArgumentList);
        Assert.Equal(
            new[]
            {
                tsv.ScreenshotPath, "stdout", "-l", "chi_sim+eng",
                "--tessdata-dir", tsv.TessdataPath, "--psm", "3", "tsv",
            },
            TesseractOcrProcessRunner.CreateStartInfo(tsv).ArgumentList);
    }

    [Fact]
    public async Task Screenshot_tsv_merges_words_into_ordered_lines_and_source_pixel_bounds()
    {
        using var directory = new TemporaryDirectory();
        var screenshot = Path.Combine(directory.Path, "capture.png");
        File.WriteAllBytes(screenshot, [1]);
        var process = new FakeProcess(new(0,
            "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n" +
            "5\t1\t1\t1\t1\t1\t10\t20\t30\t12\t90.0\tHello\n" +
            "5\t1\t1\t1\t1\t2\t45\t20\t40\t12\t80.0\tworld\n" +
            "5\t1\t1\t1\t2\t1\t12\t50\t60\t18\t95.5\t第二行\n"));
        var adapter = CreateAdapter(process);

        var result = await adapter.RecognizeAsync(
            new ScreenshotOcrEngineRequest(screenshot, "ja-JP"),
            CancellationToken.None);

        Assert.Equal(ScreenshotOcrEngineStatus.Succeeded, result.Status);
        Assert.Equal("Hello world\n第二行", result.Text);
        Assert.Collection(
            result.Lines,
            line =>
            {
                Assert.Equal("Hello world", line.Text);
                Assert.Equal(85, line.Confidence, precision: 5);
                Assert.Equal(new ScreenshotPixelBounds(10, 20, 75, 12), line.Bounds);
            },
            line =>
            {
                Assert.Equal("第二行", line.Text);
                Assert.Equal(95.5, line.Confidence, precision: 5);
                Assert.Equal(new ScreenshotPixelBounds(12, 50, 60, 18), line.Bounds);
            });
        Assert.Equal("jpn+eng", process.Request!.Languages);
        Assert.Equal(TesseractOcrOutputFormat.Tsv, process.Request.OutputFormat);
    }

    [Theory]
    [InlineData("zh-Hans", "chi_sim+eng")]
    [InlineData("zh-Hant", "chi_tra+eng")]
    [InlineData("en-US", "eng")]
    [InlineData("ja-JP", "jpn+eng")]
    [InlineData("ko-KR", "kor+eng")]
    public async Task Screenshot_ocr_selects_only_bundled_five_language_models(
        string locale,
        string expected)
    {
        using var directory = new TemporaryDirectory();
        var screenshot = Path.Combine(directory.Path, "capture.png");
        File.WriteAllBytes(screenshot, [1]);
        var process = new FakeProcess(new(0, HeaderOnly));
        var adapter = CreateAdapter(process);

        _ = await adapter.RecognizeAsync(
            new ScreenshotOcrEngineRequest(screenshot, locale),
            CancellationToken.None);

        Assert.Equal(expected, process.Request!.Languages);
    }

    [Fact]
    public async Task Empty_tsv_and_unavailable_runtime_have_stable_status_without_text_or_lines()
    {
        using var directory = new TemporaryDirectory();
        var screenshot = Path.Combine(directory.Path, "capture.png");
        File.WriteAllBytes(screenshot, [1]);
        var empty = await CreateAdapter(new FakeProcess(new(0, HeaderOnly))).RecognizeAsync(
            new ScreenshotOcrEngineRequest(screenshot, "en"),
            CancellationToken.None);
        var process = new FakeProcess(new(0, "must not run"));
        var unavailable = new TesseractScreenshotOcrAdapter(
            new TesseractRuntimeLocator(directory.Path),
            new FixedVerifier(new(false, TesseractRuntimeVerificationError.MissingLanguage)),
            process);

        var missingRuntime = await unavailable.RecognizeAsync(
            new ScreenshotOcrEngineRequest(screenshot, "en"),
            CancellationToken.None);

        Assert.Equal(ScreenshotOcrEngineStatus.Empty, empty.Status);
        Assert.Equal(string.Empty, empty.Text);
        Assert.Empty(empty.Lines);
        Assert.Equal(ScreenshotOcrEngineStatus.RuntimeUnavailable, missingRuntime.Status);
        Assert.Null(process.Request);
    }

    [Fact]
    public void Rotated_half_open_bounds_map_back_to_original_physical_pixels()
    {
        var cases = new[]
        {
            (ScreenshotImageRotation.None, new ScreenshotPixelBounds(10, 20, 30, 15),
                new ScreenshotPixelBounds(10, 20, 30, 15)),
            (ScreenshotImageRotation.Clockwise90, new ScreenshotPixelBounds(5, 10, 20, 30),
                new ScreenshotPixelBounds(10, 35, 30, 20)),
            (ScreenshotImageRotation.Clockwise180, new ScreenshotPixelBounds(10, 5, 20, 15),
                new ScreenshotPixelBounds(70, 40, 20, 15)),
            (ScreenshotImageRotation.Clockwise270, new ScreenshotPixelBounds(5, 10, 20, 30),
                new ScreenshotPixelBounds(60, 5, 30, 20)),
        };
        foreach (var (rotation, input, expected) in cases)
        {
            var mapped = ScreenshotOcrOrientationMapper.TryMapToOriginal(
                input,
                rotation,
                originalPixelWidth: 100,
                originalPixelHeight: 60,
                out var bounds);

            Assert.True(mapped);
            Assert.Equal(expected, bounds);
        }
        Assert.False(ScreenshotOcrOrientationMapper.TryMapToOriginal(
            new ScreenshotPixelBounds(50, 10, 20, 10),
            ScreenshotImageRotation.Clockwise90,
            originalPixelWidth: 100,
            originalPixelHeight: 60,
            out _));
    }

    [Fact]
    public async Task Screenshot_ocr_selects_rotated_quality_and_returns_original_pixel_bounds()
    {
        using var directory = new TemporaryDirectory();
        var original = CreatePlaceholder(directory.Path, "original.png");
        var clockwise90 = CreatePlaceholder(directory.Path, "clockwise-90.png");
        var clockwise180 = CreatePlaceholder(directory.Path, "clockwise-180.png");
        var clockwise270 = CreatePlaceholder(directory.Path, "clockwise-270.png");
        var candidates = new FixedCandidateProvider(new ScreenshotOcrImageCandidateBatch(
            originalPixelWidth: 100,
            originalPixelHeight: 60,
            [
                new(original, ScreenshotImageRotation.None, 100, 60),
                new(clockwise90, ScreenshotImageRotation.Clockwise90, 60, 100),
                new(clockwise180, ScreenshotImageRotation.Clockwise180, 100, 60),
                new(clockwise270, ScreenshotImageRotation.Clockwise270, 60, 100),
            ]));
        var process = new RoutingProcess(new Dictionary<string, TesseractOcrProcessResult>
        {
            [original] = new(0, Tsv("sideways", 42, 10, 10, 25, 12)),
            [clockwise90] = new(0, Tsv("normalized", 96, 5, 10, 20, 30)),
            [clockwise180] = new(0, Tsv("upside down", 35, 10, 5, 25, 12)),
            [clockwise270] = new(0, Tsv("other side", 38, 5, 10, 20, 30)),
        });
        var adapter = CreateAdapter(process, candidates);

        var result = await adapter.RecognizeAsync(
            new ScreenshotOcrEngineRequest(original, "en-US"),
            CancellationToken.None);

        Assert.Equal(ScreenshotOcrEngineStatus.Succeeded, result.Status);
        Assert.Equal("normalized", result.Text);
        var line = Assert.Single(result.Lines);
        Assert.Equal(new ScreenshotPixelBounds(10, 35, 30, 20), line.Bounds);
        Assert.Equal(
            new[] { original, clockwise90, clockwise180, clockwise270 },
            process.Requests.Select(request => request.ScreenshotPath));
    }

    [Fact]
    public async Task Windows_candidate_provider_physically_rotates_png_and_cleans_scratch_pixels()
    {
        using var directory = new TemporaryDirectory();
        var original = Path.Combine(directory.Path, "pixels.png");
        await WriteBgraPngAsync(
            original,
            width: 2,
            height: 3,
            BluePixels(1, 2, 3, 4, 5, 6));
        var provider = new WindowsScreenshotOcrImageCandidateProvider();
        var batch = await provider.CreateAsync(original, CancellationToken.None);
        var scratchPaths = batch.Candidates
            .Where(candidate => candidate.Rotation != ScreenshotImageRotation.None)
            .Select(candidate => candidate.ImagePath)
            .ToArray();

        try
        {
            Assert.Equal(2, batch.OriginalPixelWidth);
            Assert.Equal(3, batch.OriginalPixelHeight);
            Assert.Equal(4, batch.Candidates.Count);
            await AssertRotationPixelsAsync(
                batch,
                ScreenshotImageRotation.Clockwise90,
                expectedWidth: 3,
                expectedHeight: 2,
                [5, 3, 1, 6, 4, 2]);
            await AssertRotationPixelsAsync(
                batch,
                ScreenshotImageRotation.Clockwise180,
                expectedWidth: 2,
                expectedHeight: 3,
                [6, 5, 4, 3, 2, 1]);
            await AssertRotationPixelsAsync(
                batch,
                ScreenshotImageRotation.Clockwise270,
                expectedWidth: 3,
                expectedHeight: 2,
                [2, 4, 6, 1, 3, 5]);
            Assert.All(scratchPaths, path => Assert.True(File.Exists(path)));
        }
        finally
        {
            batch.Dispose();
        }

        Assert.True(File.Exists(original));
        Assert.All(scratchPaths, path => Assert.False(File.Exists(path)));
    }

    [Fact]
    public async Task Small_rotated_confidence_noise_conservatively_keeps_upright_result()
    {
        using var directory = new TemporaryDirectory();
        var original = CreatePlaceholder(directory.Path, "original.png");
        var rotated = CreatePlaceholder(directory.Path, "rotated.png");
        var candidates = new FixedCandidateProvider(new ScreenshotOcrImageCandidateBatch(
            originalPixelWidth: 100,
            originalPixelHeight: 60,
            [
                new(original, ScreenshotImageRotation.None, 100, 60),
                new(rotated, ScreenshotImageRotation.Clockwise180, 100, 60),
            ]));
        var adapter = CreateAdapter(
            new RoutingProcess(new Dictionary<string, TesseractOcrProcessResult>
            {
                [original] = new(0, Tsv("upright", 90, 10, 10, 30, 12)),
                [rotated] = new(0, Tsv("rotation noise", 91, 10, 10, 30, 12)),
            }),
            candidates);

        var result = await adapter.RecognizeAsync(
            new ScreenshotOcrEngineRequest(original, "en-US"),
            CancellationToken.None);

        Assert.Equal("upright", result.Text);
        Assert.Equal(new ScreenshotPixelBounds(10, 10, 30, 12), Assert.Single(result.Lines).Bounds);
    }

    [Fact]
    public async Task One_high_confidence_noise_token_cannot_beat_broad_text_coverage()
    {
        using var directory = new TemporaryDirectory();
        var original = CreatePlaceholder(directory.Path, "original.png");
        var rotated = CreatePlaceholder(directory.Path, "rotated.png");
        var candidates = new FixedCandidateProvider(new ScreenshotOcrImageCandidateBatch(
            originalPixelWidth: 100,
            originalPixelHeight: 60,
            [
                new(original, ScreenshotImageRotation.None, 100, 60),
                new(rotated, ScreenshotImageRotation.Clockwise90, 60, 100),
            ]));
        var broadCoverage = HeaderOnly
            + "5\t1\t1\t1\t1\t1\t5\t10\t18\t10\t82\tReliable\n"
            + "5\t1\t1\t1\t1\t2\t25\t10\t28\t10\t80\torientation\n"
            + "5\t1\t1\t1\t2\t1\t5\t30\t15\t10\t79\twith\n"
            + "5\t1\t1\t1\t2\t2\t22\t30\t30\t10\t81\tcoverage\n";
        var adapter = CreateAdapter(
            new RoutingProcess(new Dictionary<string, TesseractOcrProcessResult>
            {
                [original] = new(0, Tsv("X", 99, 10, 10, 8, 12)),
                [rotated] = new(0, broadCoverage),
            }),
            candidates);

        var result = await adapter.RecognizeAsync(
            new ScreenshotOcrEngineRequest(original, "en-US"),
            CancellationToken.None);

        Assert.Equal("Reliable orientation\nwith coverage", result.Text);
        Assert.Equal(2, result.Lines.Count);
    }

    private const string HeaderOnly =
        "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n";

    private static string Tsv(
        string text,
        double confidence,
        int left,
        int top,
        int width,
        int height) =>
        HeaderOnly
        + $"5\t1\t1\t1\t1\t1\t{left}\t{top}\t{width}\t{height}\t{confidence.ToString(System.Globalization.CultureInfo.InvariantCulture)}\t{text}\n";

    private static string CreatePlaceholder(string directory, string fileName)
    {
        var path = Path.Combine(directory, fileName);
        File.WriteAllBytes(path, [1]);
        return path;
    }

    private static TesseractOcrProcessRequest Request(TesseractOcrOutputFormat outputFormat) => new(
        @"C:\Program Files\VoxFlow\runtime\ocr\tesseract.exe",
        @"C:\Users\Fixture\AppData\Local\VoxFlow\Screenshots\capture.png",
        @"C:\Program Files\VoxFlow\runtime\ocr\tessdata",
        "chi_sim+eng",
        outputFormat);

    private static TesseractScreenshotOcrAdapter CreateAdapter(
        ITesseractOcrProcessRunner process,
        IScreenshotOcrImageCandidateProvider? candidates = null) => new(
        new TesseractRuntimeLocator(@"C:\Program Files\VoxFlow"),
        new FixedVerifier(new(
            true,
            null,
            ExecutablePath: @"C:\Program Files\VoxFlow\runtime\ocr\tesseract.exe",
            TessdataPath: @"C:\Program Files\VoxFlow\runtime\ocr\tessdata")),
        process,
        candidates ?? new PassthroughCandidateProvider());

    private static async Task WriteBgraPngAsync(
        string path,
        uint width,
        uint height,
        byte[] pixels)
    {
        using (File.Create(path))
        {
        }
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Straight,
            width,
            height,
            96,
            96,
            pixels);
        await encoder.FlushAsync();
    }

    private static async Task<(int Width, int Height, byte[] Pixels)> ReadBgraPngAsync(string path)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(stream);
        var pixelData = await decoder.GetPixelDataAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Straight,
            new BitmapTransform(),
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);
        return (
            checked((int)decoder.PixelWidth),
            checked((int)decoder.PixelHeight),
            pixelData.DetachPixelData());
    }

    private static async Task AssertRotationPixelsAsync(
        ScreenshotOcrImageCandidateBatch batch,
        ScreenshotImageRotation rotation,
        int expectedWidth,
        int expectedHeight,
        byte[] expectedBlueChannels)
    {
        var candidate = Assert.Single(
            batch.Candidates,
            value => value.Rotation == rotation);
        Assert.Equal(expectedWidth, candidate.PixelWidth);
        Assert.Equal(expectedHeight, candidate.PixelHeight);
        var decoded = await ReadBgraPngAsync(candidate.ImagePath);
        Assert.Equal((expectedWidth, expectedHeight), (decoded.Width, decoded.Height));
        Assert.Equal(expectedBlueChannels, BlueChannels(decoded.Pixels));
    }

    private static byte[] BluePixels(params byte[] blueValues)
    {
        var pixels = new byte[checked(blueValues.Length * 4)];
        for (var index = 0; index < blueValues.Length; index++)
        {
            pixels[index * 4] = blueValues[index];
            pixels[index * 4 + 3] = byte.MaxValue;
        }
        return pixels;
    }

    private static byte[] BlueChannels(byte[] pixels) =>
        Enumerable.Range(0, pixels.Length / 4)
            .Select(index => pixels[index * 4])
            .ToArray();

    private sealed class FixedVerifier(TesseractRuntimeVerificationResult result)
        : ITesseractRuntimeVerifier
    {
        public TesseractRuntimeVerificationResult Verify(string runtimeDirectory) => result;
    }

    private sealed class FakeProcess(TesseractOcrProcessResult result)
        : ITesseractOcrProcessRunner
    {
        public TesseractOcrProcessRequest? Request { get; private set; }

        public Task<TesseractOcrProcessResult> RunAsync(
            TesseractOcrProcessRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Request = request;
            return Task.FromResult(result);
        }
    }

    private sealed class RoutingProcess(
        IReadOnlyDictionary<string, TesseractOcrProcessResult> results)
        : ITesseractOcrProcessRunner
    {
        public List<TesseractOcrProcessRequest> Requests { get; } = [];

        public Task<TesseractOcrProcessResult> RunAsync(
            TesseractOcrProcessRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Requests.Add(request);
            return Task.FromResult(results[request.ScreenshotPath]);
        }
    }

    private sealed class PassthroughCandidateProvider : IScreenshotOcrImageCandidateProvider
    {
        public Task<ScreenshotOcrImageCandidateBatch> CreateAsync(
            string originalImagePath,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(new ScreenshotOcrImageCandidateBatch(
                originalPixelWidth: 200,
                originalPixelHeight: 200,
                [
                    new(
                        originalImagePath,
                        ScreenshotImageRotation.None,
                        PixelWidth: 200,
                        PixelHeight: 200),
                ]));
        }
    }

    private sealed class FixedCandidateProvider(ScreenshotOcrImageCandidateBatch batch)
        : IScreenshotOcrImageCandidateProvider
    {
        public Task<ScreenshotOcrImageCandidateBatch> CreateAsync(
            string originalImagePath,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(batch);
        }
    }
}
