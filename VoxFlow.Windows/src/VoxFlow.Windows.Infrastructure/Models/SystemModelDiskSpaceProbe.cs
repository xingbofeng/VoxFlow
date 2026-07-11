using VoxFlow.Windows.Application.Models;

namespace VoxFlow.Windows.Infrastructure.Models;

public sealed class SystemModelDiskSpaceProbe : IModelDiskSpaceProbe
{
    public long GetAvailableBytes(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = Path.GetFullPath(path);
        var root = Path.GetPathRoot(fullPath)
            ?? throw new InvalidOperationException("The model path has no drive root.");
        return new DriveInfo(root).AvailableFreeSpace;
    }
}
