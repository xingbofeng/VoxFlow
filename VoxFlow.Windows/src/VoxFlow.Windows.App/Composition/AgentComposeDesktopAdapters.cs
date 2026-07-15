using System.Diagnostics;
using System.IO;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Platform.Agent;
using VoxFlow.Windows.Platform.Output;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.App.Composition;

internal sealed class WindowsAgentTargetSnapshotProvider
    : IAgentComposeTargetSnapshotProvider
{
    private readonly Win32ForegroundSelectionTargetProvider targets = new(
        new WindowsForegroundSelectionApi(),
        Process.GetCurrentProcess().Id,
        TimeProvider.System);

    public ForegroundTargetSnapshot? Capture() => targets.Capture().Target;
}

internal sealed class WindowsAgentOutputClipboard(WindowsClipboardGateway clipboard)
    : IAgentOutputClipboard
{
    public bool TryCopy(string text)
    {
        try
        {
            _ = clipboard.WriteUnicodeText(text);
            return true;
        }
        catch (ClipboardOperationException)
        {
            return false;
        }
    }
}

internal sealed class WindowsAgentClipboardTextGateway(WindowsClipboardGateway clipboard)
    : IAgentClipboardTextGateway
{
    public string? ReadText() => clipboard.ReadUnicodeText();

    public void WriteText(string text) => _ = clipboard.WriteUnicodeText(text);
}

/// <summary>Windows-only bridge for the Agent's local visual fallback. A PNG
/// exists only long enough for one verified Tesseract call and is deleted in a
/// finally block; the Application layer receives text plus a stable warning,
/// never a pathname or image payload.</summary>
internal sealed class WindowsAgentVisualTextFallback : IAgentVisualTextFallback
{
    private readonly WindowCaptureAdapter capture = new(
        new DwmWindowCaptureNative(),
        new AgentTaskScreenshotStore());
    private readonly TesseractOcrAdapter ocr = new(
        new TesseractRuntimeLocator(AppContext.BaseDirectory),
        new TesseractRuntimeVerifier(),
        new TesseractOcrProcessRunner());

    public async Task<AgentVisualTextFallbackResult> ReadAsync(
        ForegroundTargetSnapshot target,
        string taskWorkspace,
        CancellationToken cancellationToken)
    {
        var captured = capture.Capture(target, taskWorkspace);
        if (!captured.Succeeded || string.IsNullOrWhiteSpace(captured.ScreenshotPath))
        {
            return new(null, CaptureWarning(captured.Status));
        }

        try
        {
            var result = await ocr.RecognizeAsync(
                captured.ScreenshotPath,
                System.Globalization.CultureInfo.CurrentUICulture.Name,
                cancellationToken).ConfigureAwait(false);
            return result.Status switch
            {
                TesseractOcrStatus.Succeeded => new(result.Text, "visual_fallback"),
                TesseractOcrStatus.Empty => new(null, "ocr_empty"),
                TesseractOcrStatus.RuntimeUnavailable => new(null, "ocr_runtime_unavailable"),
                TesseractOcrStatus.InputUnavailable => new(null, "ocr_input_unavailable"),
                TesseractOcrStatus.TimedOut => new(null, "ocr_timeout"),
                _ => new(null, "ocr_failed"),
            };
        }
        finally
        {
            TryDeleteCapture(captured.ScreenshotPath);
        }
    }

    private static string CaptureWarning(WindowCaptureStatus status) => status switch
    {
        WindowCaptureStatus.TargetClosed => "visual_target_closed",
        WindowCaptureStatus.TargetNotVisible => "visual_target_not_visible",
        WindowCaptureStatus.TargetMinimized => "visual_target_minimized",
        WindowCaptureStatus.TargetProtected => "visual_target_protected",
        WindowCaptureStatus.BoundsUnavailable => "visual_bounds_unavailable",
        WindowCaptureStatus.BlackFrame => "visual_black_frame",
        _ => "visual_capture_failed",
    };

    private static void TryDeleteCapture(string screenshotPath)
    {
        try
        {
            File.Delete(screenshotPath);
            var directory = Path.GetDirectoryName(screenshotPath);
            if (!string.IsNullOrWhiteSpace(directory)
                && Directory.Exists(directory)
                && !Directory.EnumerateFileSystemEntries(directory).Any())
            {
                Directory.Delete(directory);
            }
        }
        catch (IOException)
        {
            // The next managed-workspace cleanup retries an interrupted delete.
        }
        catch (UnauthorizedAccessException)
        {
            // OCR is a non-blocking context fallback; never expose a path here.
        }
    }
}

internal sealed class WindowsAgentUrlLauncher : IAgentUrlLauncher
{
    public bool TryOpen(Uri uri)
    {
        try
        {
            _ = Process.Start(new ProcessStartInfo(uri.AbsoluteUri)
            {
                UseShellExecute = true,
            });
            return true;
        }
        catch
        {
            return false;
        }
    }
}

internal sealed class HudAgentOutputSummaryPresenter(
    HudDictationProgressSink agentHud)
    : IAgentOutputSummaryPresenter, IAgentOutputStatusPresenter
{
    public void ShowSummary(string? text) => agentHud.ShowAgentSummary(text);

    public void ShowCopied() => agentHud.ShowAgentCopied();
}

/// <summary>Agent final output has already been handled by its output policy.
/// This intentionally discards the value passed through the generic dictation
/// lifecycle, preventing a second paste or clipboard write.</summary>
internal sealed class DiscardingAgentDictationOutput : IDictationOutput
{
    public ValueTask<OutputResult> WriteAsync(
        string text,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(new OutputResult(OutputResultKind.Copied));
    }
}

/// <summary>Agent tasks use workflow_tasks rather than dictation_history.</summary>
internal sealed class DiscardingAgentDictationHistorySink : IDictationHistorySink
{
    public ValueTask SaveAsync(
        DictationHistoryDraft draft,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.CompletedTask;
    }
}
