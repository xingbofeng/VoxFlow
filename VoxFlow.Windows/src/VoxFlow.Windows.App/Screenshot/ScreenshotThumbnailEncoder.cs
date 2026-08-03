using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Rect = System.Windows.Rect;

namespace VoxFlow.Windows.App.Screenshot;

public sealed class ScreenshotThumbnailEncoder
{
    public const int Width = 260;
    public const int Height = 150;

    public byte[] Encode(BitmapSource source)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (source.PixelWidth <= 0 || source.PixelHeight <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(source));
        }

        var scale = Math.Min(
            Width / (double)source.PixelWidth,
            Height / (double)source.PixelHeight);
        var targetWidth = source.PixelWidth * scale;
        var targetHeight = source.PixelHeight * scale;
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawRectangle(System.Windows.Media.Brushes.Transparent, null, new Rect(0, 0, Width, Height));
            drawing.DrawImage(
                source,
                new Rect(
                    (Width - targetWidth) / 2,
                    (Height - targetHeight) / 2,
                    targetWidth,
                    targetHeight));
        }
        var thumbnail = new RenderTargetBitmap(
            Width,
            Height,
            96,
            96,
            PixelFormats.Pbgra32);
        thumbnail.Render(visual);
        thumbnail.Freeze();
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(thumbnail));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }
}
