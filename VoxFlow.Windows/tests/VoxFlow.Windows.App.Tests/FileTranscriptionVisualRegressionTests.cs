using System.Globalization;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Theming;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class FileTranscriptionVisualRegressionTests
{
    private const int Width = 1260;
    private const int Height = 720;
    private const double MaximumMeanCellDifference = 8.0;
    private static readonly double[] DpiScales = [1, 1.25, 1.5, 2];
    private static readonly string[] States =
    [
        "empty", "queued", "running", "completed", "failed",
        "partially-failed", "interrupted", "translating", "translated",
        "translation-failed",
    ];

    [Fact]
    public async Task Macos_aligned_workbench_matches_light_dark_and_four_dpi_baselines()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var originalCulture = CultureInfo.CurrentUICulture;
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("en");
            try
            {
                var actual = new SortedDictionary<string, string>(StringComparer.Ordinal);
                foreach (var theme in Enum.GetValues<AppThemeMode>())
                {
                    foreach (var state in States)
                    {
                        foreach (var scale in DpiScales)
                        {
                            var key = $"{theme.ToString().ToLowerInvariant()}/{state}/{scale:0.##}";
                            actual[key] = Convert.ToBase64String(Render(theme, state, scale, key));
                        }
                    }
                }

                var updatePath = Environment.GetEnvironmentVariable(
                    "VOXFLOW_UPDATE_VISUAL_BASELINE_PATH");
                if (!string.IsNullOrWhiteSpace(updatePath))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(updatePath)!
                        ?? throw new InvalidOperationException("Baseline path has no directory."));
                    File.WriteAllText(
                        updatePath,
                        JsonSerializer.Serialize(actual, new JsonSerializerOptions { WriteIndented = true }));
                }

                var expectedPath = Path.Combine(
                    AppContext.BaseDirectory,
                    "TestResources",
                    "VisualBaselines",
                    "file-transcription-signatures.json");
                Assert.True(File.Exists(expectedPath), "The approved visual signature baseline is missing.");
                var expected = JsonSerializer.Deserialize<SortedDictionary<string, string>>(
                    File.ReadAllText(expectedPath))
                    ?? throw new InvalidDataException("Visual baseline JSON is empty.");
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
            return Task.CompletedTask;
        }, timeout: TimeSpan.FromMinutes(3));
    }

    private static byte[] Render(
        AppThemeMode theme,
        string state,
        double scale,
        string evidenceName)
    {
        var page = Page(state);
        var window = new MainWindow(
            homeDashboard: null,
            settingsPage: null,
            fileTranscriptionPage: page)
        {
            Width = Width,
            Height = Height,
        };
        window.Resources.MergedDictionaries.Add(ThemeResourceLoader.Load(theme));
        Assert.True(window.ViewModel.TryNavigate("file-transcription"));
        var root = Assert.IsAssignableFrom<FrameworkElement>(window.Content);
        root.DataContext = window.DataContext;
        root.Measure(new Size(Width, Height));
        root.Arrange(new Rect(0, 0, Width, Height));
        root.UpdateLayout();
        Assert.Equal(Width, root.ActualWidth);
        Assert.Equal(Height, root.ActualHeight);

        var pixelWidth = checked((int)Math.Round(Width * scale));
        var pixelHeight = checked((int)Math.Round(Height * scale));
        var bitmap = new RenderTargetBitmap(
            pixelWidth,
            pixelHeight,
            96 * scale,
            96 * scale,
            PixelFormats.Pbgra32);
        bitmap.Render(root);
        SaveEvidence(bitmap, evidenceName);
        return Signature(bitmap, columns: 16, rows: 9);
    }

    private static FileTranscriptionPageViewModel Page(string state)
    {
        var job = Job(state);
        var repository = new VisualJobRepository(job is null ? [] : [job]);
        return new FileTranscriptionPageViewModel(
            L10n.Localize("FileTranscriptionHeading"),
            L10n.Localize("FileTranscriptionSubtitle"),
            repository,
            queue: null,
            () => new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B),
            () => RecognitionLanguage.Automatic,
            TimeProvider.System);
    }

    private static FileTranscriptionJob? Job(string state)
    {
        if (state == "empty") return null;
        var status = state switch
        {
            "queued" => FileTranscriptionJobStatus.Queued,
            "running" => FileTranscriptionJobStatus.Running,
            "failed" => FileTranscriptionJobStatus.Failed,
            "partially-failed" => FileTranscriptionJobStatus.PartiallyFailed,
            "interrupted" => FileTranscriptionJobStatus.Interrupted,
            _ => FileTranscriptionJobStatus.Completed,
        };
        var hasResult = status is FileTranscriptionJobStatus.Completed
            or FileTranscriptionJobStatus.PartiallyFailed;
        var translationStatus = state switch
        {
            "translating" => FileTranscriptionTranslationStatus.Running,
            "translated" => FileTranscriptionTranslationStatus.Completed,
            "translation-failed" => FileTranscriptionTranslationStatus.Failed,
            _ => FileTranscriptionTranslationStatus.NotRequested,
        };
        return new FileTranscriptionJob(
            "job-visual",
            Path.GetTempFileName(),
            "quarterly-review.mp4",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status,
            durationMs: 125_000,
            progress: status switch
            {
                FileTranscriptionJobStatus.Running => 0.45,
                FileTranscriptionJobStatus.PartiallyFailed => 0.67,
                FileTranscriptionJobStatus.Completed => 1,
                _ => 0,
            },
            finalText: hasResult
                ? "A concise original transcript used to verify selectable result text and layout."
                : null,
            errorCode: status == FileTranscriptionJobStatus.Failed
                ? FileTranscriptionErrorCode.ProviderNetworkFailure
                : null,
            segmentCount: 4,
            segmentCompleted: status switch
            {
                FileTranscriptionJobStatus.Running => 1,
                FileTranscriptionJobStatus.PartiallyFailed => 3,
                FileTranscriptionJobStatus.Completed => 4,
                _ => 0,
            },
            translationStatus: translationStatus,
            translatedText: translationStatus == FileTranscriptionTranslationStatus.Completed
                ? "用于验证双栏对比布局的简洁译文。"
                : null,
            translationTargetLanguage: translationStatus == FileTranscriptionTranslationStatus.Completed
                ? "zh-Hans"
                : null,
            translationErrorCode: translationStatus == FileTranscriptionTranslationStatus.Failed
                ? FileTranscriptionErrorCode.TranslationFailure
                : null,
            translationUpdatedAtUnixMs: translationStatus == FileTranscriptionTranslationStatus.NotRequested
                ? null
                : 1);
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

    private static double MeanDifference(byte[] expected, byte[] actual)
    {
        Assert.Equal(expected.Length, actual.Length);
        return expected.Zip(actual, (left, right) => Math.Abs(left - right)).Average();
    }

    private static void SaveEvidence(BitmapSource bitmap, string name)
    {
        var root = Environment.GetEnvironmentVariable("VOXFLOW_VISUAL_EVIDENCE_ROOT");
        if (string.IsNullOrWhiteSpace(root)) return;
        Directory.CreateDirectory(root);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(Path.Combine(
            root,
            name.Replace('/', '-') + ".png"));
        encoder.Save(stream);
    }

    private sealed class VisualJobRepository(IReadOnlyList<FileTranscriptionJob> initial)
        : IFileTranscriptionJobRepository
    {
        private readonly List<FileTranscriptionJob> jobs = [.. initial];
        public void Create(FileTranscriptionJob job) => jobs.Add(job);
        public FileTranscriptionJob? Get(string id) => jobs.SingleOrDefault(job => job.Id == id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs.ToArray();
        public bool Update(FileTranscriptionJob job) => false;
        public bool Delete(string id) => false;
        public int MarkRunningAsInterrupted() => 0;
    }
}
