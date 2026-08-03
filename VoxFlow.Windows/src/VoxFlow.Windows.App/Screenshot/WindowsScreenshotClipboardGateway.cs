using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;

namespace VoxFlow.Windows.App.Screenshot;

/// <summary>
/// Owns a dedicated STA thread for the real WPF clipboard boundary.
/// </summary>
public sealed class WindowsScreenshotClipboardGateway
    : IScreenshotClipboardGateway, IDisposable
{
    private const int ClipboardCannotOpenHResult = unchecked((int)0x800401D0);
    private readonly StaClipboardDispatcher dispatcher = new();

    public IScreenshotClipboardSnapshot CaptureSnapshot() => InvokeClipboard(() =>
        new WpfScreenshotClipboardSnapshot(System.Windows.Clipboard.GetDataObject()));

    public void Publish(ScreenshotClipboardPayload payload)
    {
        ArgumentNullException.ThrowIfNull(payload);
        InvokeClipboard(() =>
        {
            var data = new System.Windows.DataObject();
            using var png = new MemoryStream(payload.CopyPngBytes(), writable: false);
            using var dibV5 = new MemoryStream(payload.CopyDibV5Bytes(), writable: false);
            data.SetData(ScreenshotClipboardPayload.PngFormatName, png, autoConvert: false);
            data.SetData(ScreenshotClipboardPayload.DibV5FormatName, dibV5, autoConvert: false);
            data.SetData(
                ScreenshotClipboardPayload.BitmapFormatName,
                payload.Bitmap,
                autoConvert: true);
            System.Windows.Clipboard.SetDataObject(data, copy: true);
        });
    }

    public void Restore(IScreenshotClipboardSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot is not WpfScreenshotClipboardSnapshot wpfSnapshot)
        {
            throw new ArgumentException(
                "The snapshot was not created by this clipboard gateway.",
                nameof(snapshot));
        }

        InvokeClipboard(() =>
        {
            if (wpfSnapshot.Data is null)
            {
                System.Windows.Clipboard.Clear();
                return;
            }

            System.Windows.Clipboard.SetDataObject(wpfSnapshot.Data, copy: true);
        });
    }

    public void Dispose() => dispatcher.Dispose();

    private void InvokeClipboard(Action action) => InvokeClipboard(() =>
    {
        action();
        return true;
    });

    private T InvokeClipboard<T>(Func<T> action)
    {
        try
        {
            return dispatcher.Invoke(action);
        }
        catch (ScreenshotClipboardBusyException)
        {
            throw;
        }
        catch (COMException exception) when (
            exception.HResult == ClipboardCannotOpenHResult)
        {
            throw new ScreenshotClipboardBusyException(
                "The Windows clipboard is currently locked.",
                exception);
        }
        catch (ExternalException exception) when (
            exception.ErrorCode == ClipboardCannotOpenHResult)
        {
            throw new ScreenshotClipboardBusyException(
                "The Windows clipboard is currently locked.",
                exception);
        }
        catch (Exception exception)
        {
            throw new ScreenshotClipboardException(
                "The Windows screenshot clipboard operation failed.",
                exception);
        }
    }

    private sealed class WpfScreenshotClipboardSnapshot(System.Windows.IDataObject? data)
        : IScreenshotClipboardSnapshot
    {
        public System.Windows.IDataObject? Data { get; } = data;

        public void Dispose()
        {
        }
    }

    private sealed class StaClipboardDispatcher : IDisposable
    {
        private readonly BlockingCollection<Action> work = [];
        private readonly Thread thread;
        private bool disposed;

        public StaClipboardDispatcher()
        {
            thread = new Thread(Run)
            {
                IsBackground = true,
                Name = "VoxFlow screenshot clipboard STA",
            };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }

        public T Invoke<T>(Func<T> action)
        {
            ArgumentNullException.ThrowIfNull(action);
            ObjectDisposedException.ThrowIf(disposed, this);

            var completion = new TaskCompletionSource<T>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            try
            {
                work.Add(() =>
                {
                    try
                    {
                        completion.SetResult(action());
                    }
                    catch (Exception exception)
                    {
                        completion.SetException(exception);
                    }
                });
            }
            catch (InvalidOperationException exception)
            {
                throw new ObjectDisposedException(
                    nameof(StaClipboardDispatcher),
                    exception.Message);
            }

            return completion.Task.GetAwaiter().GetResult();
        }

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            work.CompleteAdding();
            if (Thread.CurrentThread != thread)
            {
                _ = thread.Join(TimeSpan.FromSeconds(3));
            }

            work.Dispose();
        }

        private void Run()
        {
            foreach (var action in work.GetConsumingEnumerable())
            {
                action();
            }
        }
    }
}
