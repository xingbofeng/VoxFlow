using System.IO;

namespace VoxFlow.Windows.Testing;

public sealed class TemporaryDirectory : IDisposable
{
    private int _isDisposed;

    public TemporaryDirectory(string? parentDirectory = null)
    {
        var parent = parentDirectory ?? System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "VoxFlow.Windows.Tests");
        Directory.CreateDirectory(parent);

        Path = System.IO.Path.Combine(parent, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _isDisposed, 1) != 0)
        {
            return;
        }

        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
