using VoxFlow.Windows.Platform.Screenshot;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class ScreenshotCaptureGeometryTests
{
    [Fact]
    public void Frozen_frame_owns_pixels_instead_of_exposing_the_capture_zone_buffer()
    {
        var zone = SolidBgra(width: 2, height: 1, blue: 11);
        var frame = new FrozenDisplayFrame(
            "DISPLAY1",
            "adapter-1",
            new CapturePixelRect(0, 0, 2, 1),
            rotationDegrees: 0,
            stride: 8,
            zone);

        zone[0] = 99;

        Assert.Equal(11, frame.Bgra.Span[0]);
    }

    [Fact]
    public void Crop_stitches_negative_origin_displays_in_physical_pixels()
    {
        var left = new FrozenDisplayFrame(
            "DISPLAY2",
            "adapter-a",
            new CapturePixelRect(-2, 0, 2, 2),
            rotationDegrees: 0,
            stride: 8,
            SolidBgra(2, 2, blue: 17));
        var right = new FrozenDisplayFrame(
            "DISPLAY1",
            "adapter-b",
            new CapturePixelRect(0, 0, 2, 2),
            rotationDegrees: 0,
            stride: 8,
            SolidBgra(2, 2, blue: 29));

        var crop = new FrozenDesktop([left, right])
            .Crop(new CapturePixelRect(-1, 0, 2, 2));

        Assert.Equal(2, crop.Width);
        Assert.Equal(2, crop.Height);
        Assert.Equal(8, crop.Stride);
        Assert.Equal(17, crop.Bgra.Span[0]);
        Assert.Equal(29, crop.Bgra.Span[4]);
        Assert.Equal(17, crop.Bgra.Span[8]);
        Assert.Equal(29, crop.Bgra.Span[12]);
    }

    [Fact]
    public void Crop_keeps_virtual_desktop_gaps_opaque_black()
    {
        var left = new FrozenDisplayFrame(
            "DISPLAY1",
            "adapter",
            new CapturePixelRect(0, 0, 1, 1),
            0,
            4,
            SolidBgra(1, 1, blue: 4));
        var right = new FrozenDisplayFrame(
            "DISPLAY2",
            "adapter",
            new CapturePixelRect(2, 0, 1, 1),
            0,
            4,
            SolidBgra(1, 1, blue: 8));

        var crop = new FrozenDesktop([left, right])
            .Crop(new CapturePixelRect(0, 0, 3, 1));

        Assert.Equal(new byte[]
        {
            4, 0, 0, 255,
            0, 0, 0, 255,
            8, 0, 0, 255,
        }, crop.Bgra.ToArray());
    }

    private static byte[] SolidBgra(int width, int height, byte blue)
    {
        var pixels = new byte[checked(width * height * 4)];
        for (var index = 0; index < pixels.Length; index += 4)
        {
            pixels[index] = blue;
            pixels[index + 3] = byte.MaxValue;
        }
        return pixels;
    }
}
