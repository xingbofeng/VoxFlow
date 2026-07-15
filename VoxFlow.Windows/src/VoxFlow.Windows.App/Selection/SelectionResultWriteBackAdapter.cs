using VoxFlow.Windows.Platform.Selection;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Selection;

/// <summary>Connects a result panel to the sole safe Windows selection write
/// path. The panel never sends input itself; every action revalidates the
/// original target, reports false only when the service copied as fallback,
/// and throws when neither guarded write nor safe copy succeeded.</summary>
public sealed class SelectionResultWriteBackAdapter : ISelectionResultWriter
{
    private readonly SelectionSnapshot snapshot;
    private readonly SelectionWriteBackService writeBack;

    public SelectionResultWriteBackAdapter(
        SelectionSnapshot snapshot,
        SelectionWriteBackService writeBack)
    {
        this.snapshot = snapshot ?? throw new ArgumentNullException(nameof(snapshot));
        this.writeBack = writeBack ?? throw new ArgumentNullException(nameof(writeBack));
    }

    public async Task<bool> ReplaceAsync(string text, CancellationToken cancellationToken) =>
        Project(await writeBack.ReplaceAsync(snapshot, text, cancellationToken).ConfigureAwait(false));

    public async Task<bool> InsertAfterAsync(string text, CancellationToken cancellationToken) =>
        Project(await writeBack.InsertAfterAsync(snapshot, text, cancellationToken).ConfigureAwait(false));

    private static bool Project(SelectionWriteBackResult result)
    {
        if (!result.WrittenToOriginal && !result.CopiedFallback)
        {
            throw new InvalidOperationException(
                "The selection result could not be written or copied safely.");
        }

        return result.WrittenToOriginal;
    }
}
