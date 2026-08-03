using System.Globalization;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.App.Selection;

public static class SelectionFailurePresentation
{
    public static string From(
        SelectionTextReadStatus status,
        CultureInfo? culture = null) => status switch
    {
        SelectionTextReadStatus.SecureElement =>
            L10n.Localize("SelectionFailureSecureField", culture),
        SelectionTextReadStatus.TargetChanged =>
            L10n.Localize("SelectionFailureTargetChanged", culture),
        SelectionTextReadStatus.TerminalNotSupported =>
            L10n.Localize("SelectionFailureTerminal", culture),
        SelectionTextReadStatus.ClipboardBusy =>
            L10n.Localize("SelectionFailureClipboardBusy", culture),
        SelectionTextReadStatus.CopySendFailed =>
            L10n.Localize("SelectionFailureCopyFailed", culture),
        _ => L10n.Localize("SelectionFailureNoSelection", culture),
    };
}
