using System.Globalization;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.App.Screenshot;

/// <summary>
/// Privacy-safe readiness data. It intentionally omits display names, window
/// titles, image/text content, filesystem paths and provider credentials.
/// </summary>
public sealed record ScreenshotReadinessSnapshot(
    string CaptureDependencyVersion,
    ScreenshotCaptureReadinessStatus CaptureStatus,
    int ActiveDisplayCount,
    int MappedDisplayCount,
    int AdapterCount,
    bool OcrRuntimeAvailable,
    TesseractRuntimeVerificationError? OcrRuntimeError,
    int OcrLanguageCount)
{
    public string ToSafeDiagnosticCode() => string.Join(
        ' ',
        "screenshot.readiness",
        $"captureDependency={NormalizeVersion(CaptureDependencyVersion)}",
        $"captureStatus={CaptureStatus}",
        $"activeDisplays={ActiveDisplayCount.ToString(CultureInfo.InvariantCulture)}",
        $"mappedDisplays={MappedDisplayCount.ToString(CultureInfo.InvariantCulture)}",
        $"adapters={AdapterCount.ToString(CultureInfo.InvariantCulture)}",
        $"ocrRuntime={(OcrRuntimeAvailable ? "ready" : "unavailable")}",
        $"ocrError={OcrRuntimeError?.ToString() ?? "none"}",
        $"ocrLanguages={OcrLanguageCount.ToString(CultureInfo.InvariantCulture)}");

    private static string NormalizeVersion(string value) =>
        Version.TryParse(value, out var version)
            ? version.ToString()
            : "unknown";
}

public static class ScreenshotReadinessDiagnostics
{
    public static ScreenshotReadinessSnapshot Capture(
        Dx11ScreenshotFrameSource frames,
        string installationRoot)
    {
        ArgumentNullException.ThrowIfNull(frames);
        ArgumentException.ThrowIfNullOrWhiteSpace(installationRoot);
        var capture = frames.GetReadiness();
        var runtime = new TesseractRuntimeLocator(installationRoot);
        var ocr = new TesseractRuntimeVerifier().Verify(runtime.RuntimeDirectory);
        return new ScreenshotReadinessSnapshot(
            Dx11ScreenshotFrameSource.CaptureDependencyVersion,
            capture.Status,
            capture.ActiveDisplayCount,
            capture.MappedDisplayCount,
            capture.AdapterCount,
            ocr.IsValid,
            ocr.Error,
            ocr.IsValid
                ? TesseractRuntimeVerifier.RequiredLanguageModels.Count
                : 0);
    }
}
