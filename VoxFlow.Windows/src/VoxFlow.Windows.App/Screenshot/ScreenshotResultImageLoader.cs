using System.IO;
using System.Windows.Media.Imaging;

namespace VoxFlow.Windows.App.Screenshot;

public interface IScreenshotResultImageLoader
{
    Task<BitmapSource?> LoadPreviewAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Decodes an expanded-panel preview off the UI thread. OnLoad releases the
/// source file before publication and Freeze makes the result dispatcher-safe.
/// </summary>
public sealed class ScreenshotResultImageLoader : IScreenshotResultImageLoader
{
    public const int MaximumPreviewPixelDimension = 880;

    public async Task<BitmapSource?> LoadPreviewAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absoluteImagePath);
        if (!Path.IsPathFullyQualified(absoluteImagePath))
        {
            throw new ArgumentException(
                "The screenshot result image path must be absolute.",
                nameof(absoluteImagePath));
        }
        cancellationToken.ThrowIfCancellationRequested();
        return await Task.Run(
            () => Decode(absoluteImagePath, cancellationToken),
            cancellationToken).ConfigureAwait(false);
    }

    private static BitmapSource? Decode(
        string absoluteImagePath,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!File.Exists(absoluteImagePath))
        {
            return null;
        }
        try
        {
            int sourceWidth;
            int sourceHeight;
            using (var metadataStream = new FileStream(
                absoluteImagePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete))
            {
                var decoder = BitmapDecoder.Create(
                    metadataStream,
                    BitmapCreateOptions.PreservePixelFormat,
                    BitmapCacheOption.OnDemand);
                sourceWidth = decoder.Frames[0].PixelWidth;
                sourceHeight = decoder.Frames[0].PixelHeight;
            }
            using var stream = new FileStream(
                absoluteImagePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.CreateOptions = BitmapCreateOptions.PreservePixelFormat;
            if (Math.Max(sourceWidth, sourceHeight) > MaximumPreviewPixelDimension)
            {
                if (sourceWidth >= sourceHeight)
                {
                    bitmap.DecodePixelWidth = MaximumPreviewPixelDimension;
                }
                else
                {
                    bitmap.DecodePixelHeight = MaximumPreviewPixelDimension;
                }
            }
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            cancellationToken.ThrowIfCancellationRequested();
            bitmap.Freeze();
            return bitmap;
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or InvalidOperationException)
        {
            return null;
        }
    }
}
