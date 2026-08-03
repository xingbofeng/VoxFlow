using Windows.Graphics.Imaging;
using Windows.Storage;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Infrastructure.Ocr;

internal enum ScreenshotImageRotation
{
    None = 0,
    Clockwise90 = 90,
    Clockwise180 = 180,
    Clockwise270 = 270,
}

internal sealed record ScreenshotOcrImageCandidate(
    string ImagePath,
    ScreenshotImageRotation Rotation,
    int PixelWidth,
    int PixelHeight);

internal sealed class ScreenshotOcrImageCandidateBatch : IDisposable
{
    private readonly IReadOnlyList<string> ownedPaths;
    private int disposed;

    public ScreenshotOcrImageCandidateBatch(
        int originalPixelWidth,
        int originalPixelHeight,
        IReadOnlyList<ScreenshotOcrImageCandidate> candidates,
        IReadOnlyList<string>? ownedPaths = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(originalPixelWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(originalPixelHeight);
        ArgumentNullException.ThrowIfNull(candidates);
        if (candidates.Count == 0)
        {
            throw new ArgumentException("At least one OCR orientation candidate is required.", nameof(candidates));
        }
        OriginalPixelWidth = originalPixelWidth;
        OriginalPixelHeight = originalPixelHeight;
        Candidates = Array.AsReadOnly(candidates.ToArray());
        this.ownedPaths = Array.AsReadOnly((ownedPaths ?? []).ToArray());
    }

    public int OriginalPixelWidth { get; }

    public int OriginalPixelHeight { get; }

    public IReadOnlyList<ScreenshotOcrImageCandidate> Candidates { get; }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }
        foreach (var path in ownedPaths)
        {
            TryDelete(path);
        }
    }

    internal static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // OCR scratch pixels are best-effort cleanup and never become managed assets.
        }
    }
}

internal interface IScreenshotOcrImageCandidateProvider
{
    Task<ScreenshotOcrImageCandidateBatch> CreateAsync(
        string originalImagePath,
        CancellationToken cancellationToken);
}

/// <summary>
/// Builds physical PNG rotations with the Windows Imaging Component projection.
/// The bundled runtime intentionally does not ship osd.traineddata, so OCR quality
/// across these fixed candidates is the orientation signal.
/// </summary>
internal sealed class WindowsScreenshotOcrImageCandidateProvider
    : IScreenshotOcrImageCandidateProvider
{
    private static readonly ScreenshotImageRotation[] Rotations =
    [
        ScreenshotImageRotation.Clockwise90,
        ScreenshotImageRotation.Clockwise180,
        ScreenshotImageRotation.Clockwise270,
    ];

    public async Task<ScreenshotOcrImageCandidateBatch> CreateAsync(
        string originalImagePath,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(originalImagePath);
        cancellationToken.ThrowIfCancellationRequested();
        var originalPath = Path.GetFullPath(originalImagePath);
        var (width, height) = await ReadDimensionsAsync(originalPath, cancellationToken)
            .ConfigureAwait(false);
        List<ScreenshotOcrImageCandidate> candidates =
        [
            new(originalPath, ScreenshotImageRotation.None, width, height),
        ];
        List<string> ownedPaths = [];
        try
        {
            foreach (var rotation in Rotations)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var rotatedPath = CreateScratchPath();
                ownedPaths.Add(rotatedPath);
                await RotateAsync(originalPath, rotatedPath, rotation, cancellationToken)
                    .ConfigureAwait(false);
                var swapsAxes = rotation is ScreenshotImageRotation.Clockwise90
                    or ScreenshotImageRotation.Clockwise270;
                candidates.Add(new(
                    rotatedPath,
                    rotation,
                    swapsAxes ? height : width,
                    swapsAxes ? width : height));
            }
            return new ScreenshotOcrImageCandidateBatch(
                width,
                height,
                candidates,
                ownedPaths);
        }
        catch
        {
            foreach (var path in ownedPaths)
            {
                ScreenshotOcrImageCandidateBatch.TryDelete(path);
            }
            throw;
        }
    }

    private static async Task<(int Width, int Height)> ReadDimensionsAsync(
        string path,
        CancellationToken cancellationToken)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        cancellationToken.ThrowIfCancellationRequested();
        using var stream = await file.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(stream);
        cancellationToken.ThrowIfCancellationRequested();
        return (checked((int)decoder.PixelWidth), checked((int)decoder.PixelHeight));
    }

    private static async Task RotateAsync(
        string sourcePath,
        string destinationPath,
        ScreenshotImageRotation rotation,
        CancellationToken cancellationToken)
    {
        using (File.Create(destinationPath))
        {
        }
        var sourceFile = await StorageFile.GetFileFromPathAsync(sourcePath);
        var destinationFile = await StorageFile.GetFileFromPathAsync(destinationPath);
        cancellationToken.ThrowIfCancellationRequested();
        using var sourceStream = await sourceFile.OpenReadAsync();
        using var destinationStream = await destinationFile.OpenAsync(FileAccessMode.ReadWrite);
        var decoder = await BitmapDecoder.CreateAsync(sourceStream);
        var encoder = await BitmapEncoder.CreateForTranscodingAsync(destinationStream, decoder);
        encoder.BitmapTransform.Rotation = rotation switch
        {
            ScreenshotImageRotation.Clockwise90 => BitmapRotation.Clockwise90Degrees,
            ScreenshotImageRotation.Clockwise180 => BitmapRotation.Clockwise180Degrees,
            ScreenshotImageRotation.Clockwise270 => BitmapRotation.Clockwise270Degrees,
            _ => throw new ArgumentOutOfRangeException(nameof(rotation)),
        };
        cancellationToken.ThrowIfCancellationRequested();
        await encoder.FlushAsync();
        cancellationToken.ThrowIfCancellationRequested();
    }

    private static string CreateScratchPath()
    {
        var directory = Path.Combine(Path.GetTempPath(), "VoxFlow", "ocr-orientation");
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, $"{Guid.NewGuid():N}.png");
    }
}

/// <summary>
/// Converts half-open Tesseract rectangles from a physically rotated candidate
/// back into the original screenshot's physical-pixel coordinate space.
/// </summary>
internal static class ScreenshotOcrOrientationMapper
{
    public static bool HasExpectedDimensions(
        ScreenshotOcrImageCandidate candidate,
        int originalPixelWidth,
        int originalPixelHeight)
    {
        ArgumentNullException.ThrowIfNull(candidate);
        var swapsAxes = candidate.Rotation is ScreenshotImageRotation.Clockwise90
            or ScreenshotImageRotation.Clockwise270;
        return candidate.PixelWidth == (swapsAxes ? originalPixelHeight : originalPixelWidth)
            && candidate.PixelHeight == (swapsAxes ? originalPixelWidth : originalPixelHeight);
    }

    public static bool TryMapToOriginal(
        ScreenshotPixelBounds rotatedBounds,
        ScreenshotImageRotation rotation,
        int originalPixelWidth,
        int originalPixelHeight,
        out ScreenshotPixelBounds originalBounds)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(originalPixelWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(originalPixelHeight);
        originalBounds = default;
        var swapsAxes = rotation is ScreenshotImageRotation.Clockwise90
            or ScreenshotImageRotation.Clockwise270;
        var rotatedWidth = swapsAxes ? originalPixelHeight : originalPixelWidth;
        var rotatedHeight = swapsAxes ? originalPixelWidth : originalPixelHeight;
        int right;
        int bottom;
        try
        {
            right = checked(rotatedBounds.X + rotatedBounds.Width);
            bottom = checked(rotatedBounds.Y + rotatedBounds.Height);
        }
        catch (OverflowException)
        {
            return false;
        }
        if (right > rotatedWidth || bottom > rotatedHeight)
        {
            return false;
        }

        originalBounds = rotation switch
        {
            ScreenshotImageRotation.None => rotatedBounds,
            ScreenshotImageRotation.Clockwise90 => new ScreenshotPixelBounds(
                rotatedBounds.Y,
                originalPixelHeight - right,
                rotatedBounds.Height,
                rotatedBounds.Width),
            ScreenshotImageRotation.Clockwise180 => new ScreenshotPixelBounds(
                originalPixelWidth - right,
                originalPixelHeight - bottom,
                rotatedBounds.Width,
                rotatedBounds.Height),
            ScreenshotImageRotation.Clockwise270 => new ScreenshotPixelBounds(
                originalPixelWidth - bottom,
                rotatedBounds.X,
                rotatedBounds.Height,
                rotatedBounds.Width),
            _ => throw new ArgumentOutOfRangeException(nameof(rotation)),
        };
        return true;
    }
}
