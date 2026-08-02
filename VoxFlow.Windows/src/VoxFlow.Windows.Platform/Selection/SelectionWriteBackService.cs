using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Platform.Selection;

public interface ISelectionWriteRevalidator
{
    SelectionTargetRevalidationResult RevalidateAndReselect(SelectionSnapshot snapshot);
}

public interface ISelectionWriteOutput
{
    ValueTask<OutputResult> PasteAsync(string text, CancellationToken cancellationToken);
}

public interface ISelectionWriteClipboard
{
    bool TryCopy(string text);
}

public sealed record SelectionWriteBackResult(
    bool WrittenToOriginal,
    bool CopiedFallback,
    SelectionTargetRevalidationStatus? RevalidationStatus,
    OutputResult? Output);

/// <summary>
/// The only selection write path. It first activates and revalidates the
/// frozen target, then recreates its UIA range before pasting. Every failure
/// path copies the unprefixed display text and never sends input to a newly
/// foregrounded window.
/// </summary>
public sealed class SelectionWriteBackService
{
    private readonly ISelectionTargetActivation activation;
    private readonly ISelectionWriteRevalidator revalidator;
    private readonly ISelectionWriteOutput output;
    private readonly ISelectionWriteClipboard clipboard;

    public SelectionWriteBackService(
        ISelectionTargetActivation activation,
        ISelectionWriteRevalidator revalidator,
        ISelectionWriteOutput output,
        ISelectionWriteClipboard clipboard)
    {
        this.activation = activation ?? throw new ArgumentNullException(nameof(activation));
        this.revalidator = revalidator ?? throw new ArgumentNullException(nameof(revalidator));
        this.output = output ?? throw new ArgumentNullException(nameof(output));
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
    }

    public ValueTask<SelectionWriteBackResult> ReplaceAsync(
        SelectionSnapshot snapshot,
        string displayedText,
        CancellationToken cancellationToken) => WriteAsync(snapshot, displayedText, prefix: "", cancellationToken);

    public ValueTask<SelectionWriteBackResult> InsertAfterAsync(
        SelectionSnapshot snapshot,
        string displayedText,
        CancellationToken cancellationToken) => WriteAsync(snapshot, displayedText, prefix: "\n", cancellationToken);

    private async ValueTask<SelectionWriteBackResult> WriteAsync(
        SelectionSnapshot snapshot,
        string displayedText,
        string prefix,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentException.ThrowIfNullOrWhiteSpace(displayedText);
        cancellationToken.ThrowIfCancellationRequested();
        if (!snapshot.IsEditable || !snapshot.AllowsReselection)
        {
            return CopyFallback(displayedText, SelectionTargetRevalidationStatus.NotEditable, null);
        }
        if (!activation.Activate(snapshot.Target)
            || !activation.IsStillTarget(snapshot.Target))
        {
            return CopyFallback(displayedText, SelectionTargetRevalidationStatus.TargetChanged, null);
        }

        var verification = revalidator.RevalidateAndReselect(snapshot);
        if (!verification.CanWrite)
        {
            return CopyFallback(displayedText, verification.Status, null);
        }

        if (!activation.IsStillTarget(snapshot.Target))
        {
            return CopyFallback(displayedText, SelectionTargetRevalidationStatus.TargetChanged, null);
        }

        var result = await output.PasteAsync(prefix + displayedText, cancellationToken).ConfigureAwait(false);
        return result.Kind == OutputResultKind.Inserted
            ? new SelectionWriteBackResult(true, false, SelectionTargetRevalidationStatus.Ready, result)
            : CopyFallback(displayedText, SelectionTargetRevalidationStatus.UipiBlocked, result);
    }

    private SelectionWriteBackResult CopyFallback(
        string displayedText,
        SelectionTargetRevalidationStatus status,
        OutputResult? outputResult) => new(
        WrittenToOriginal: false,
        CopiedFallback: clipboard.TryCopy(displayedText),
        RevalidationStatus: status,
        Output: outputResult);
}

public sealed class SelectionTargetRevalidatorAdapter(SelectionTargetRevalidator revalidator)
    : ISelectionWriteRevalidator
{
    private readonly SelectionTargetRevalidator revalidator = revalidator
        ?? throw new ArgumentNullException(nameof(revalidator));

    public SelectionTargetRevalidationResult RevalidateAndReselect(SelectionSnapshot snapshot) =>
        revalidator.RevalidateAndReselect(snapshot);
}
