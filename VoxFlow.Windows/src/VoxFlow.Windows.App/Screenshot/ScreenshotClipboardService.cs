using System.Buffers.Binary;
using System.Globalization;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotClipboardWriteStatus
{
    Copied,
    Busy,
    Failed,
}

public sealed record ScreenshotClipboardWriteResult(
    ScreenshotClipboardWriteStatus Status,
    string? ErrorMessage);

public sealed class ScreenshotClipboardBusyException : Exception
{
    public ScreenshotClipboardBusyException(string message)
        : base(message)
    {
    }

    public ScreenshotClipboardBusyException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public sealed class ScreenshotClipboardException : Exception
{
    public ScreenshotClipboardException(string message)
        : base(message)
    {
    }

    public ScreenshotClipboardException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public interface IScreenshotClipboardSnapshot : IDisposable
{
}

public interface IScreenshotClipboardGateway
{
    IScreenshotClipboardSnapshot CaptureSnapshot();

    void Publish(ScreenshotClipboardPayload payload);

    void Restore(IScreenshotClipboardSnapshot snapshot);
}

public interface IScreenshotClipboardRetryDelay
{
    ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken);
}

public interface IScreenshotImageClipboardWriter
{
    Task<ScreenshotClipboardWriteResult> CopyImageAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default);
}

internal interface IScreenshotClipboardPayloadFactory
{
    ScreenshotClipboardPayload Create(ScreenshotRenderResult render);

    ScreenshotClipboardPayload CreateFromImageFile(string absoluteImagePath);
}

internal sealed class ScreenshotClipboardPayloadFactory : IScreenshotClipboardPayloadFactory
{
    public static ScreenshotClipboardPayloadFactory Instance { get; } = new();

    public ScreenshotClipboardPayload Create(ScreenshotRenderResult render) =>
        ScreenshotClipboardPayload.Create(render);

    public ScreenshotClipboardPayload CreateFromImageFile(string absoluteImagePath) =>
        ScreenshotClipboardPayload.CreateFromImageFile(absoluteImagePath);
}

/// <summary>
/// Process-safe entry point used by result and media surfaces. Each operation
/// owns and disposes the dedicated STA clipboard gateway after its bounded
/// retry transaction completes.
/// </summary>
public sealed class ReliableScreenshotImageClipboardWriter
    : IScreenshotImageClipboardWriter
{
    private readonly SemaphoreSlim copyGate = new(1, 1);

    public static ReliableScreenshotImageClipboardWriter Instance { get; } = new();

    private ReliableScreenshotImageClipboardWriter()
    {
    }

    public async Task<ScreenshotClipboardWriteResult> CopyImageAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default)
    {
        await copyGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            using var service = new ScreenshotClipboardService();
            return await service.CopyImageAsync(
                absoluteImagePath,
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            copyGate.Release();
        }
    }
}

public sealed class ScreenshotClipboardRetryPolicy
{
    public static ScreenshotClipboardRetryPolicy Default { get; } = new(
        maxAttempts: 4,
        initialDelay: TimeSpan.FromMilliseconds(20),
        backoffFactor: 2,
        maximumDelay: TimeSpan.FromMilliseconds(160));

    public ScreenshotClipboardRetryPolicy(
        int maxAttempts,
        TimeSpan initialDelay,
        double backoffFactor,
        TimeSpan maximumDelay)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(maxAttempts, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(initialDelay, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfLessThan(backoffFactor, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(maximumDelay, initialDelay);

        MaxAttempts = maxAttempts;
        InitialDelay = initialDelay;
        BackoffFactor = backoffFactor;
        MaximumDelay = maximumDelay;
    }

    public int MaxAttempts { get; }

    public TimeSpan InitialDelay { get; }

    public double BackoffFactor { get; }

    public TimeSpan MaximumDelay { get; }

    public TimeSpan DelayAfterAttempt(int failedAttempt)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(failedAttempt, 1);
        var scaledTicks = InitialDelay.Ticks * Math.Pow(BackoffFactor, failedAttempt - 1);
        var ticks = scaledTicks >= MaximumDelay.Ticks
            ? MaximumDelay.Ticks
            : (long)scaledTicks;
        return TimeSpan.FromTicks(ticks);
    }
}

/// <summary>
/// Immutable clipboard formats derived from one source-resolution render.
/// </summary>
public sealed class ScreenshotClipboardPayload
{
    private const int BitmapV5HeaderSize = 124;
    private const int CfDibV5 = 17;
    private const uint BiBitFields = 3;
    private const uint LcsSrgb = 0x73524742;
    private const uint LcsGraphics = 2;
    private readonly byte[] pngBytes;
    private readonly byte[] dibV5Bytes;
    private readonly IReadOnlyList<string> formats;

    private ScreenshotClipboardPayload(
        BitmapSource bitmap,
        byte[] pngBytes,
        byte[] dibV5Bytes)
    {
        Bitmap = bitmap;
        this.pngBytes = pngBytes;
        this.dibV5Bytes = dibV5Bytes;
        formats = Array.AsReadOnly(
            [PngFormatName, DibV5FormatName, BitmapFormatName]);
    }

    public const string PngFormatName = "PNG";

    public static string DibV5FormatName { get; } =
        System.Windows.DataFormats.GetDataFormat(CfDibV5).Name;

    public static string BitmapFormatName => System.Windows.DataFormats.Bitmap;

    public BitmapSource Bitmap { get; }

    public IReadOnlyList<string> Formats => formats;

    public static ScreenshotClipboardPayload Create(ScreenshotRenderResult render)
    {
        ArgumentNullException.ThrowIfNull(render);
        var bitmap = ConvertToBgra32(render.Bitmap);
        return new ScreenshotClipboardPayload(
            bitmap,
            render.CopyPngBytes(),
            EncodeDibV5(bitmap));
    }

    public static ScreenshotClipboardPayload CreateFromImageFile(string absoluteImagePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absoluteImagePath);
        if (!Path.IsPathFullyQualified(absoluteImagePath))
        {
            throw new ArgumentException(
                "The screenshot clipboard image path must be absolute.",
                nameof(absoluteImagePath));
        }

        using var stream = new FileStream(
            absoluteImagePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        var decoder = BitmapDecoder.Create(
            stream,
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad);
        var bitmap = ConvertToBgra32(decoder.Frames[0]);
        return new ScreenshotClipboardPayload(
            bitmap,
            EncodePng(bitmap),
            EncodeDibV5(bitmap));
    }

    public byte[] CopyPngBytes() => pngBytes.ToArray();

    public byte[] CopyDibV5Bytes() => dibV5Bytes.ToArray();

    private static BitmapSource ConvertToBgra32(BitmapSource source)
    {
        if (source.Format == PixelFormats.Bgra32 && source.IsFrozen)
        {
            return source;
        }

        if (source.Format == PixelFormats.Bgra32)
        {
            var frozen = source.Clone();
            frozen.Freeze();
            return frozen;
        }

        var converted = new FormatConvertedBitmap(
            source,
            PixelFormats.Bgra32,
            destinationPalette: null,
            alphaThreshold: 0);
        converted.Freeze();
        return converted;
    }

    private static byte[] EncodePng(BitmapSource bitmap)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static byte[] EncodeDibV5(BitmapSource bitmap)
    {
        var width = bitmap.PixelWidth;
        var height = bitmap.PixelHeight;
        var stride = checked(width * 4);
        var imageSize = checked(stride * height);
        var sourcePixels = new byte[imageSize];
        bitmap.CopyPixels(sourcePixels, stride, 0);

        var dib = new byte[checked(BitmapV5HeaderSize + imageSize)];
        WriteInt32(dib, 0, BitmapV5HeaderSize);
        WriteInt32(dib, 4, width);
        WriteInt32(dib, 8, height);
        BinaryPrimitives.WriteUInt16LittleEndian(dib.AsSpan(12, 2), 1);
        BinaryPrimitives.WriteUInt16LittleEndian(dib.AsSpan(14, 2), 32);
        WriteUInt32(dib, 16, BiBitFields);
        WriteInt32(dib, 20, imageSize);
        WriteInt32(dib, 24, PixelsPerMeter(bitmap.DpiX));
        WriteInt32(dib, 28, PixelsPerMeter(bitmap.DpiY));
        WriteUInt32(dib, 40, 0x00ff0000);
        WriteUInt32(dib, 44, 0x0000ff00);
        WriteUInt32(dib, 48, 0x000000ff);
        WriteUInt32(dib, 52, 0xff000000);
        WriteUInt32(dib, 56, LcsSrgb);
        WriteUInt32(dib, 108, LcsGraphics);

        for (var sourceRow = 0; sourceRow < height; sourceRow++)
        {
            var destinationRow = height - sourceRow - 1;
            Buffer.BlockCopy(
                sourcePixels,
                sourceRow * stride,
                dib,
                BitmapV5HeaderSize + (destinationRow * stride),
                stride);
        }

        return dib;
    }

    private static int PixelsPerMeter(double dpi) =>
        checked((int)Math.Round(dpi / 0.0254, MidpointRounding.AwayFromZero));

    private static void WriteInt32(byte[] buffer, int offset, int value) =>
        BinaryPrimitives.WriteInt32LittleEndian(buffer.AsSpan(offset, 4), value);

    private static void WriteUInt32(byte[] buffer, int offset, uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(buffer.AsSpan(offset, 4), value);
}

/// <summary>
/// Copies one rendered screenshot without losing the previous clipboard when publication fails.
/// </summary>
public sealed class ScreenshotClipboardService
    : IDisposable, IScreenshotImageClipboardWriter
{
    private readonly IScreenshotClipboardGateway gateway;
    private readonly ScreenshotClipboardRetryPolicy retryPolicy;
    private readonly IScreenshotClipboardRetryDelay delay;
    private readonly IScreenshotClipboardPayloadFactory payloadFactory;
    private readonly bool ownsGateway;
    private readonly SemaphoreSlim copyGate = new(1, 1);
    private bool disposed;

    public ScreenshotClipboardService()
        : this(
            new WindowsScreenshotClipboardGateway(),
            ScreenshotClipboardRetryPolicy.Default,
            SystemScreenshotClipboardRetryDelay.Instance,
            ScreenshotClipboardPayloadFactory.Instance,
            ownsGateway: true)
    {
    }

    public ScreenshotClipboardService(
        IScreenshotClipboardGateway gateway,
        ScreenshotClipboardRetryPolicy retryPolicy,
        IScreenshotClipboardRetryDelay? delay = null)
        : this(
            gateway,
            retryPolicy,
            delay ?? SystemScreenshotClipboardRetryDelay.Instance,
            ScreenshotClipboardPayloadFactory.Instance,
            ownsGateway: false)
    {
    }

    internal ScreenshotClipboardService(
        IScreenshotClipboardGateway gateway,
        ScreenshotClipboardRetryPolicy retryPolicy,
        IScreenshotClipboardRetryDelay delay,
        IScreenshotClipboardPayloadFactory payloadFactory)
        : this(
            gateway,
            retryPolicy,
            delay,
            payloadFactory,
            ownsGateway: false)
    {
    }

    private ScreenshotClipboardService(
        IScreenshotClipboardGateway gateway,
        ScreenshotClipboardRetryPolicy retryPolicy,
        IScreenshotClipboardRetryDelay delay,
        IScreenshotClipboardPayloadFactory payloadFactory,
        bool ownsGateway)
    {
        this.gateway = gateway ?? throw new ArgumentNullException(nameof(gateway));
        this.retryPolicy = retryPolicy ?? throw new ArgumentNullException(nameof(retryPolicy));
        this.delay = delay ?? throw new ArgumentNullException(nameof(delay));
        this.payloadFactory = payloadFactory
            ?? throw new ArgumentNullException(nameof(payloadFactory));
        this.ownsGateway = ownsGateway;
    }

    public async Task<ScreenshotClipboardWriteResult> CopyAsync(
        ScreenshotRenderResult render,
        CultureInfo? culture = null,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(render);
        cancellationToken.ThrowIfCancellationRequested();
        var payload = await Task.Run(
            () => payloadFactory.Create(render),
            cancellationToken).ConfigureAwait(false);
        return await CopyPayloadAsync(
            payload,
            culture,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<ScreenshotClipboardWriteResult> CopyImageAsync(
        string absoluteImagePath,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentException.ThrowIfNullOrWhiteSpace(absoluteImagePath);
        cancellationToken.ThrowIfCancellationRequested();
        var payload = await Task.Run(
            () => payloadFactory.CreateFromImageFile(absoluteImagePath),
            cancellationToken).ConfigureAwait(false);
        return await CopyPayloadAsync(
            payload,
            CultureInfo.CurrentUICulture,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<ScreenshotClipboardWriteResult> CopyPayloadAsync(
        ScreenshotClipboardPayload payload,
        CultureInfo? culture,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(payload);
        await copyGate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            IScreenshotClipboardSnapshot? snapshot = null;

            try
            {
                for (var attempt = 1; attempt <= retryPolicy.MaxAttempts; attempt++)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    try
                    {
                        snapshot ??= gateway.CaptureSnapshot();
                        gateway.Publish(payload);
                        return new ScreenshotClipboardWriteResult(
                            ScreenshotClipboardWriteStatus.Copied,
                            ErrorMessage: null);
                    }
                    catch (ScreenshotClipboardBusyException) when (attempt < retryPolicy.MaxAttempts)
                    {
                        await delay.DelayAsync(
                            retryPolicy.DelayAfterAttempt(attempt),
                            cancellationToken).ConfigureAwait(false);
                    }
                    catch (ScreenshotClipboardBusyException)
                    {
                        await TryRestoreAsync(snapshot).ConfigureAwait(false);
                        return new ScreenshotClipboardWriteResult(
                            ScreenshotClipboardWriteStatus.Busy,
                            L10n.Localize("ScreenshotClipboardBusy", culture));
                    }
                    catch (ScreenshotClipboardException)
                    {
                        await TryRestoreAsync(snapshot).ConfigureAwait(false);
                        return new ScreenshotClipboardWriteResult(
                            ScreenshotClipboardWriteStatus.Failed,
                            L10n.Localize("ScreenshotClipboardFailed", culture));
                    }
                }

                throw new InvalidOperationException("The clipboard retry loop did not terminate.");
            }
            catch (OperationCanceledException)
            {
                await TryRestoreAsync(snapshot).ConfigureAwait(false);
                throw;
            }
            finally
            {
                snapshot?.Dispose();
            }
        }
        finally
        {
            copyGate.Release();
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        if (ownsGateway && gateway is IDisposable disposableGateway)
        {
            disposableGateway.Dispose();
        }
    }

    private async Task TryRestoreAsync(IScreenshotClipboardSnapshot? snapshot)
    {
        if (snapshot is null)
        {
            return;
        }

        for (var attempt = 1; attempt <= retryPolicy.MaxAttempts; attempt++)
        {
            try
            {
                gateway.Restore(snapshot);
                return;
            }
            catch (ScreenshotClipboardBusyException) when (attempt < retryPolicy.MaxAttempts)
            {
                await delay.DelayAsync(
                    retryPolicy.DelayAfterAttempt(attempt),
                    CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception exception) when (
                exception is ScreenshotClipboardBusyException
                    or ScreenshotClipboardException)
            {
                return;
            }
        }
    }

    private sealed class SystemScreenshotClipboardRetryDelay : IScreenshotClipboardRetryDelay
    {
        public static SystemScreenshotClipboardRetryDelay Instance { get; } = new();

        public async ValueTask DelayAsync(
            TimeSpan delay,
            CancellationToken cancellationToken) =>
            await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
    }
}
