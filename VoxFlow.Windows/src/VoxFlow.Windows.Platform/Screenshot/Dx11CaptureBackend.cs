using ScreenCaptureNet = ScreenCapture.NET;

namespace VoxFlow.Windows.Platform.Screenshot;

internal sealed record Dx11AdapterDescriptor(
    int Index,
    string Id,
    string Name,
    int VendorId,
    int DeviceId);

internal sealed record Dx11DisplayDescriptor(
    string Id,
    string DeviceName,
    int Width,
    int Height,
    int RotationDegrees,
    Dx11AdapterDescriptor Adapter);

internal interface IDx11CaptureBackendFactory
{
    IDx11CaptureBackend Create();
}

internal interface IDx11CaptureBackend : IDisposable
{
    IReadOnlyList<Dx11AdapterDescriptor> GetAdapters();

    IReadOnlyList<Dx11DisplayDescriptor> GetDisplays(Dx11AdapterDescriptor adapter);

    IDx11DisplayCapture CreateDisplayCapture(Dx11DisplayDescriptor display, int nativeTimeoutMilliseconds);
}

internal interface IDx11DisplayCapture : IDisposable
{
    Dx11DisplayDescriptor Display { get; }

    int Width { get; }

    int Height { get; }

    int Stride { get; }

    bool TryCapture();

    /// <summary>
    /// Copies the current zone while it is locked. Callers must only invoke this after
    /// <see cref="TryCapture"/> returned true for the same attempt.
    /// </summary>
    byte[] CopySuccessfulFrame();
}

internal sealed class ScreenCaptureNetDx11BackendFactory : IDx11CaptureBackendFactory
{
    public static ScreenCaptureNetDx11BackendFactory Instance { get; } = new();

    private ScreenCaptureNetDx11BackendFactory()
    {
    }

    public IDx11CaptureBackend Create() => new ScreenCaptureNetDx11Backend();
}

/// <summary>Thin, replaceable boundary around the LGPL ScreenCapture.NET API.</summary>
internal sealed class ScreenCaptureNetDx11Backend : IDx11CaptureBackend
{
    private readonly ScreenCaptureNet.DX11ScreenCaptureService service = new();
    private readonly Dictionary<int, ScreenCaptureNet.GraphicsCard> nativeAdapters = [];
    private readonly Dictionary<string, ScreenCaptureNet.Display> nativeDisplays =
        new(StringComparer.Ordinal);
    private bool disposed;

    public IReadOnlyList<Dx11AdapterDescriptor> GetAdapters()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        var adapters = new List<Dx11AdapterDescriptor>();
        foreach (var adapter in service.GetGraphicsCards())
        {
            nativeAdapters[adapter.Index] = adapter;
            adapters.Add(new Dx11AdapterDescriptor(
                adapter.Index,
                CreateAdapterId(adapter),
                adapter.Name,
                adapter.VendorId,
                adapter.DeviceId));
        }
        return adapters;
    }

    public IReadOnlyList<Dx11DisplayDescriptor> GetDisplays(Dx11AdapterDescriptor adapter)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(adapter);
        if (!nativeAdapters.TryGetValue(adapter.Index, out var nativeAdapter))
        {
            throw new ArgumentException("The adapter did not originate from this capture backend.", nameof(adapter));
        }

        var displays = new List<Dx11DisplayDescriptor>();
        foreach (var display in service.GetDisplays(nativeAdapter))
        {
            var id = CreateDisplayId(adapter, display);
            nativeDisplays[id] = display;
            displays.Add(new Dx11DisplayDescriptor(
                id,
                display.DeviceName,
                display.Width,
                display.Height,
                (int)display.Rotation,
                adapter));
        }
        return displays;
    }

    public IDx11DisplayCapture CreateDisplayCapture(
        Dx11DisplayDescriptor display,
        int nativeTimeoutMilliseconds)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(display);
        if (nativeTimeoutMilliseconds is < 1 or > 1_000)
        {
            throw new ArgumentOutOfRangeException(nameof(nativeTimeoutMilliseconds));
        }
        if (!nativeDisplays.TryGetValue(display.Id, out var nativeDisplay))
        {
            throw new ArgumentException("The display did not originate from this capture backend.", nameof(display));
        }

        var capture = service.GetScreenCapture(nativeDisplay);
        capture.Timeout = nativeTimeoutMilliseconds;
        return new ScreenCaptureNetDx11DisplayCapture(display, capture);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        nativeAdapters.Clear();
        nativeDisplays.Clear();
        service.Dispose();
    }

    private static string CreateAdapterId(ScreenCaptureNet.GraphicsCard adapter) =>
        $"{adapter.Index}:{adapter.VendorId:X8}:{adapter.DeviceId:X8}";

    private static string CreateDisplayId(
        Dx11AdapterDescriptor adapter,
        ScreenCaptureNet.Display display) =>
        $"{adapter.Id}:{display.Index}:{display.DeviceName.ToUpperInvariant()}";
}

internal sealed class ScreenCaptureNetDx11DisplayCapture : IDx11DisplayCapture
{
    private readonly ScreenCaptureNet.DX11ScreenCapture capture;
    private readonly ScreenCaptureNet.ICaptureZone zone;
    private bool disposed;

    public ScreenCaptureNetDx11DisplayCapture(
        Dx11DisplayDescriptor display,
        ScreenCaptureNet.DX11ScreenCapture capture)
    {
        Display = display ?? throw new ArgumentNullException(nameof(display));
        this.capture = capture ?? throw new ArgumentNullException(nameof(capture));
        zone = capture.RegisterCaptureZone(0, 0, display.Width, display.Height);
    }

    public Dx11DisplayDescriptor Display { get; }

    public int Width => zone.Width;

    public int Height => zone.Height;

    public int Stride => zone.Stride;

    public bool TryCapture()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        return capture.CaptureScreen();
    }

    public byte[] CopySuccessfulFrame()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        using var zoneLock = zone.Lock();
        return zone.RawBuffer.ToArray();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        _ = ((ScreenCaptureNet.IScreenCapture)capture).UnregisterCaptureZone(zone);
    }
}
