using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Platform.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotMosaicCompositorTests
{
    [Fact]
    public async Task Four_k_pattern_keeps_one_true_source_sample_per_block()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            const int width = 3840;
            const int height = 2160;
            const int blockSize = 8;
            var source = Source(width, height);

            var pattern = ScreenshotMosaicCompositor.CreatePattern(
                source,
                blockSize,
                anchorX: 0,
                anchorY: 0);

            Assert.Equal(width / blockSize, pattern.Bitmap.PixelWidth);
            Assert.Equal(height / blockSize, pattern.Bitmap.PixelHeight);
            Assert.Equal(
                (long)width * height * 4 / blockSize / blockSize,
                pattern.ByteCount);
            Assert.True(pattern.Bitmap.IsFrozen);
            Assert.Equal(0, pattern.CanvasBounds.Left);
            Assert.Equal(0, pattern.CanvasBounds.Top);
            Assert.Equal(width, pattern.CanvasBounds.Width);
            Assert.Equal(height, pattern.CanvasBounds.Height);
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Drag_cache_is_bounded_to_one_source_frame_across_many_anchors_and_sizes()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var source = Source(384, 216);
            var cache = new ScreenshotMosaicPatternCache();

            for (var step = 0; step < 2_000; step++)
            {
                cache.GetOrCreate(
                    source,
                    blockSize: 2 + (step % 15),
                    anchorX: step,
                    anchorY: step * 7);
                Assert.InRange(cache.CachedByteCount, 1, cache.ByteCapacity);
            }

            Assert.Equal((long)source.Width * source.Height * 4, cache.ByteCapacity);
            Assert.True(cache.Count < 2_000);
            return Task.CompletedTask;
        });
    }

    [Fact]
    public async Task Equivalent_grid_phases_share_the_same_pattern_and_new_source_resets_cache()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var firstSource = Source(96, 64);
            var cache = new ScreenshotMosaicPatternCache();

            var first = cache.GetOrCreate(firstSource, 8, anchorX: 3, anchorY: 5);
            var equivalent = cache.GetOrCreate(firstSource, 8, anchorX: 83, anchorY: 61);

            Assert.Same(first, equivalent);
            Assert.Equal(1, cache.Count);
            Assert.Equal(3, first.CanvasBounds.Left);
            Assert.Equal(5, first.CanvasBounds.Top);

            var secondSource = Source(48, 32);
            var replacement = cache.GetOrCreate(secondSource, 8, anchorX: 3, anchorY: 5);

            Assert.NotSame(first, replacement);
            Assert.Equal(1, cache.Count);
            Assert.Equal((long)secondSource.Width * secondSource.Height * 4, cache.ByteCapacity);
            return Task.CompletedTask;
        });
    }

    private static FrozenScreenshot Source(int width, int height)
    {
        var stride = checked(width * 4);
        var pixels = new byte[checked(stride * height)];
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var offset = checked((y * stride) + (x * 4));
                pixels[offset] = checked((byte)(x % 251));
                pixels[offset + 1] = checked((byte)(y % 241));
                pixels[offset + 2] = checked((byte)((x + y) % 239));
                pixels[offset + 3] = byte.MaxValue;
            }
        }
        return new FrozenScreenshot(width, height, stride, pixels);
    }
}
