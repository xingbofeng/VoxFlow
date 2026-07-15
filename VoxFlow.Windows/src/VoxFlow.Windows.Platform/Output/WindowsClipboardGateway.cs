using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Output;

public sealed class WindowsClipboardGateway
    : IClipboardGateway, ISelectionClipboardGateway, IDisposable
{
    private const string OwnershipFormat = "VoxFlow.Windows.ClipboardTransaction.Owner";
    private readonly StaClipboardDispatcher dispatcher = new();

    public IClipboardSnapshot CaptureSnapshot() => InvokeClipboard(() =>
        new WindowsClipboardSnapshot(System.Windows.Forms.Clipboard.GetDataObject()));

    public ClipboardWriteReceipt WriteUnicodeText(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return InvokeClipboard(() =>
        {
            var marker = Guid.NewGuid().ToString("N");
            var data = new System.Windows.Forms.DataObject();
            data.SetData(System.Windows.Forms.DataFormats.UnicodeText, text);
            data.SetData(OwnershipFormat, autoConvert: false, marker);
            System.Windows.Forms.Clipboard.SetDataObject(
                data,
                copy: true,
                retryTimes: 10,
                retryDelay: 10);
            return new ClipboardWriteReceipt(
                NativeMethods.GetClipboardSequenceNumber(),
                marker);
        });
    }

    public bool IsCurrent(ClipboardWriteReceipt receipt)
    {
        ArgumentNullException.ThrowIfNull(receipt);
        if (receipt.SequenceNumber == 0)
        {
            return false;
        }

        try
        {
            return InvokeClipboard(() =>
            {
                var sequenceBefore = NativeMethods.GetClipboardSequenceNumber();
                if (sequenceBefore != receipt.SequenceNumber)
                {
                    return false;
                }

                var data = System.Windows.Forms.Clipboard.GetDataObject();
                var marker = data?.GetData(OwnershipFormat, autoConvert: false) as string;
                var sequenceAfter = NativeMethods.GetClipboardSequenceNumber();
                return sequenceAfter == sequenceBefore
                    && string.Equals(
                        marker,
                        receipt.OwnershipMarker,
                        StringComparison.Ordinal);
            });
        }
        catch (ClipboardOperationException)
        {
            return false;
        }
    }

    public uint GetSequenceNumber() => InvokeClipboard(
        NativeMethods.GetClipboardSequenceNumber);

    public string? ReadUnicodeText() => InvokeClipboard(() =>
    {
        var before = NativeMethods.GetClipboardSequenceNumber();
        var data = System.Windows.Forms.Clipboard.GetDataObject();
        var text = data?.GetData(
            System.Windows.Forms.DataFormats.UnicodeText,
            autoConvert: false) as string;
        var after = NativeMethods.GetClipboardSequenceNumber();
        return before == after ? text : null;
    });

    public void Restore(IClipboardSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot is not WindowsClipboardSnapshot windowsSnapshot)
        {
            throw new ArgumentException(
                "The snapshot was not created by this clipboard gateway.",
                nameof(snapshot));
        }

        InvokeClipboard(() =>
        {
            if (windowsSnapshot.DataObject is null)
            {
                System.Windows.Forms.Clipboard.Clear();
                return;
            }

            System.Windows.Forms.Clipboard.SetDataObject(
                windowsSnapshot.DataObject,
                copy: true,
                retryTimes: 10,
                retryDelay: 10);
        });
    }

    public void Dispose() => dispatcher.Dispose();

    private void InvokeClipboard(Action action)
    {
        try
        {
            dispatcher.Invoke(action);
        }
        catch (ClipboardOperationException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new ClipboardOperationException(
                "The Windows clipboard operation failed.",
                exception);
        }
    }

    private T InvokeClipboard<T>(Func<T> action)
    {
        try
        {
            return dispatcher.Invoke(action);
        }
        catch (ClipboardOperationException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new ClipboardOperationException(
                "The Windows clipboard operation failed.",
                exception);
        }
    }

    private sealed class WindowsClipboardSnapshot(
        System.Windows.Forms.IDataObject? dataObject) : IClipboardSnapshot
    {
        public System.Windows.Forms.IDataObject? DataObject { get; } = dataObject;

        public void Dispose()
        {
        }
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern uint GetClipboardSequenceNumber();
    }

    private sealed class StaClipboardDispatcher : IDisposable
    {
        private readonly BlockingCollection<Action> work = new();
        private readonly Thread thread;
        private bool disposed;

        public StaClipboardDispatcher()
        {
            thread = new Thread(Run)
            {
                IsBackground = true,
                Name = "VoxFlow clipboard STA",
            };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }

        public void Invoke(Action action) => Invoke(() =>
        {
            action();
            return true;
        });

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
