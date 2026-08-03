using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotReadinessDiagnosticsTests
{
    [Fact]
    public void Safe_diagnostic_exposes_only_counts_and_stable_statuses()
    {
        var diagnostic = new ScreenshotReadinessSnapshot(
            "3.0.0.0 C:\\private\\capture.png",
            ScreenshotCaptureReadinessStatus.Ready,
            ActiveDisplayCount: 2,
            MappedDisplayCount: 2,
            AdapterCount: 1,
            OcrRuntimeAvailable: false,
            TesseractRuntimeVerificationError.MissingLanguage,
            OcrLanguageCount: 0).ToSafeDiagnosticCode();

        Assert.Contains("captureDependency=unknown", diagnostic);
        Assert.Contains("activeDisplays=2", diagnostic);
        Assert.Contains("ocrError=MissingLanguage", diagnostic);
        Assert.DoesNotContain("\\", diagnostic);
        Assert.DoesNotContain(":", diagnostic);
        Assert.DoesNotContain("private", diagnostic, StringComparison.OrdinalIgnoreCase);
    }
}
