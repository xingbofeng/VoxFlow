using VoxFlow.Windows.Application.Output;

namespace VoxFlow.Windows.App.Home;

internal sealed class WpfTextClipboardWriter : ITextClipboardWriter
{
    public void WriteText(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        System.Windows.Clipboard.SetText(
            text,
            System.Windows.TextDataFormat.UnicodeText);
    }
}
