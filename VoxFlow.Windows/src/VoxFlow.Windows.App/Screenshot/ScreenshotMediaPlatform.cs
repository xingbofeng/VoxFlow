using System.Diagnostics;
using System.IO;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.App.Dialogs;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotAssetAvailability
{
    Available,
    Missing,
    Unreadable,
}

public sealed class ScreenshotImageLoadResult
{
    public ScreenshotImageLoadResult(
        BitmapSource? image,
        ScreenshotAssetAvailability availability)
    {
        if (availability == ScreenshotAssetAvailability.Available && image is null)
        {
            throw new ArgumentException(
                "An available screenshot asset requires a decoded image.",
                nameof(image));
        }
        if (availability != ScreenshotAssetAvailability.Available && image is not null)
        {
            throw new ArgumentException(
                "An unavailable screenshot asset cannot expose an image.",
                nameof(image));
        }

        Image = image;
        Availability = availability;
    }

    public BitmapSource? Image { get; }

    public ScreenshotAssetAvailability Availability { get; }
}

public static class ScreenshotMediaActions
{
    public const string CopyImage = "copy-image";
    public const string CopyText = "copy-text";
    public const string Favorite = "favorite";
    public const string Delete = "delete";
    public const string SaveAs = "save-as";
    public const string Reveal = "reveal";
    public const string Reprocess = "reprocess";
}

public interface IScreenshotMediaPlatform
{
    ScreenshotAssetAvailability GetAssetAvailability(string absolutePath);

    ScreenshotImageLoadResult LoadImage(string absolutePath);

    Task CopyImageAsync(string absolutePath, CancellationToken cancellationToken);

    Task CopyTextAsync(string text, CancellationToken cancellationToken);

    Task<bool> SaveImageAsAsync(
        string absolutePath,
        string suggestedFileName,
        CancellationToken cancellationToken);

    Task RevealInExplorerAsync(string absolutePath, CancellationToken cancellationToken);

    Task<bool> ConfirmDeleteAsync(
        string title,
        string message,
        CancellationToken cancellationToken);
}

public sealed class WpfScreenshotMediaPlatform : IScreenshotMediaPlatform
{
    private readonly IScreenshotImageClipboardWriter imageClipboard;

    public WpfScreenshotMediaPlatform()
        : this(ReliableScreenshotImageClipboardWriter.Instance)
    {
    }

    public WpfScreenshotMediaPlatform(IScreenshotImageClipboardWriter imageClipboard)
    {
        this.imageClipboard = imageClipboard
            ?? throw new ArgumentNullException(nameof(imageClipboard));
    }

    public ScreenshotAssetAvailability GetAssetAvailability(string absolutePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        if (!File.Exists(absolutePath))
        {
            return ScreenshotAssetAvailability.Missing;
        }

        try
        {
            using var stream = new FileStream(
                absolutePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            var decoder = BitmapDecoder.Create(
                stream,
                BitmapCreateOptions.DelayCreation | BitmapCreateOptions.IgnoreColorProfile,
                BitmapCacheOption.None);
            return decoder.Frames.Count > 0
                && decoder.Frames[0].PixelWidth > 0
                && decoder.Frames[0].PixelHeight > 0
                    ? ScreenshotAssetAvailability.Available
                    : ScreenshotAssetAvailability.Unreadable;
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or InvalidOperationException
                or ArgumentException
                or FormatException)
        {
            return ScreenshotAssetAvailability.Unreadable;
        }
    }

    public ScreenshotImageLoadResult LoadImage(string absolutePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        if (!File.Exists(absolutePath))
        {
            return new ScreenshotImageLoadResult(
                null,
                ScreenshotAssetAvailability.Missing);
        }

        try
        {
            using var stream = new FileStream(
                absolutePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.CreateOptions = BitmapCreateOptions.PreservePixelFormat;
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            bitmap.Freeze();
            return new ScreenshotImageLoadResult(
                bitmap,
                ScreenshotAssetAvailability.Available);
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or InvalidOperationException)
        {
            return new ScreenshotImageLoadResult(
                null,
                ScreenshotAssetAvailability.Unreadable);
        }
    }

    public async Task CopyImageAsync(
        string absolutePath,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        cancellationToken.ThrowIfCancellationRequested();

        var result = await imageClipboard.CopyImageAsync(
            absolutePath,
            cancellationToken).ConfigureAwait(false);
        switch (result.Status)
        {
            case ScreenshotClipboardWriteStatus.Copied:
                return;
            case ScreenshotClipboardWriteStatus.Busy:
                throw new ScreenshotClipboardBusyException(
                    result.ErrorMessage ?? "The Windows clipboard is currently locked.");
            case ScreenshotClipboardWriteStatus.Failed:
                throw new ScreenshotClipboardException(
                    result.ErrorMessage ?? "The screenshot clipboard operation failed.");
            default:
                throw new ArgumentOutOfRangeException(nameof(result.Status));
        }
    }

    public Task CopyTextAsync(string text, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        cancellationToken.ThrowIfCancellationRequested();
        System.Windows.Clipboard.SetText(text, System.Windows.TextDataFormat.UnicodeText);
        return Task.CompletedTask;
    }

    public async Task<bool> SaveImageAsAsync(
        string absolutePath,
        string suggestedFileName,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(suggestedFileName);
        cancellationToken.ThrowIfCancellationRequested();
        if (!File.Exists(absolutePath))
        {
            throw new FileNotFoundException(
                "The managed screenshot asset is unavailable.",
                absolutePath);
        }

        var dialog = new SaveFileDialog
        {
            AddExtension = true,
            CheckPathExists = true,
            DefaultExt = ".png",
            FileName = suggestedFileName,
            Filter = L10n.Localize("ScreenshotPngFileFilter"),
            OverwritePrompt = true,
            Title = L10n.ScreenshotSaveAs,
        };
        if (dialog.ShowDialog() != true)
        {
            return false;
        }

        var destination = Path.GetFullPath(dialog.FileName);
        if (string.Equals(
                Path.GetFullPath(absolutePath),
                destination,
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var directory = Path.GetDirectoryName(destination)
            ?? throw new IOException("The selected screenshot destination has no directory.");
        var temporary = Path.Combine(
            directory,
            $".{Path.GetFileName(destination)}.{Guid.NewGuid():N}.tmp");
        try
        {
            await using (var source = new FileStream(
                absolutePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 64 * 1024,
                FileOptions.Asynchronous | FileOptions.SequentialScan))
            await using (var target = new FileStream(
                temporary,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 64 * 1024,
                FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await source.CopyToAsync(target, cancellationToken).ConfigureAwait(true);
                await target.FlushAsync(cancellationToken).ConfigureAwait(true);
                target.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporary, destination, overwrite: true);
            return true;
        }
        finally
        {
            try
            {
                File.Delete(temporary);
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                // The destination is already committed; a best-effort temp cleanup is sufficient.
            }
        }
    }

    public Task RevealInExplorerAsync(
        string absolutePath,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        cancellationToken.ThrowIfCancellationRequested();
        if (!File.Exists(absolutePath))
        {
            throw new FileNotFoundException(
                "The managed screenshot asset is unavailable.",
                absolutePath);
        }

        var startInfo = new ProcessStartInfo("explorer.exe")
        {
            UseShellExecute = true,
        };
        startInfo.ArgumentList.Add("/select," + absolutePath);
        _ = Process.Start(startInfo)
            ?? throw new InvalidOperationException("File Explorer could not be opened.");
        return Task.CompletedTask;
    }

    public Task<bool> ConfirmDeleteAsync(
        string title,
        string message,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        ArgumentException.ThrowIfNullOrWhiteSpace(message);
        cancellationToken.ThrowIfCancellationRequested();
        var confirmed = VoxFlowDialogWindow.ShowConfirm(
            System.Windows.Application.Current?.MainWindow,
            title,
            message,
            L10n.Localize("ScreenshotDelete"));
        return Task.FromResult(confirmed);
    }
}
