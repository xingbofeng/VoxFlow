using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotResultImageLoaderTests
{
    [Fact]
    public async Task Expanded_preview_is_scaled_loaded_and_frozen_without_holding_the_source_file()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            $"VoxFlow-result-preview-{Guid.NewGuid():N}.png");
        try
        {
            await WriteLargePngAsync(path, width: 1600, height: 900);

            var image = await new ScreenshotResultImageLoader().LoadPreviewAsync(path);

            Assert.NotNull(image);
            Assert.True(image.IsFrozen);
            Assert.Equal(ScreenshotResultImageLoader.MaximumPreviewPixelDimension, image.PixelWidth);
            Assert.Equal(495, image.PixelHeight);
            File.Delete(path);
            Assert.False(File.Exists(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static Task WriteLargePngAsync(string path, int width, int height) =>
        StaWpfTestHost.RunAsync(_ =>
        {
            var stride = checked(width * 4);
            var pixels = new byte[checked(stride * height)];
            for (var index = 0; index < pixels.Length; index += 4)
            {
                pixels[index] = 0x40;
                pixels[index + 1] = 0x80;
                pixels[index + 2] = 0xc0;
                pixels[index + 3] = 0xff;
            }
            var bitmap = BitmapSource.Create(
                width,
                height,
                96,
                96,
                PixelFormats.Bgra32,
                palette: null,
                pixels,
                stride);
            bitmap.Freeze();
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var stream = new FileStream(
                path,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None);
            encoder.Save(stream);
            return Task.CompletedTask;
        });
}
