using System.Globalization;
using VoxFlow.Windows.App.Selection;
using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.App.Tests;

public sealed class SelectionFailurePresentationTests
{
    [Theory]
    [InlineData(SelectionTextReadStatus.NoSelection, "Select text in another app")]
    [InlineData(SelectionTextReadStatus.SecureElement, "secure fields")]
    [InlineData(SelectionTextReadStatus.TargetChanged, "original window changed")]
    [InlineData(SelectionTextReadStatus.ClipboardBusy, "Clipboard is busy")]
    [InlineData(SelectionTextReadStatus.TerminalNotSupported, "Ctrl+C wasn't sent")]
    public void Failure_messages_are_specific_and_never_include_untrusted_window_or_clipboard_text(
        SelectionTextReadStatus status,
        string expectedFragment)
    {
        var message = SelectionFailurePresentation.From(
            status,
            CultureInfo.GetCultureInfo("en"));

        Assert.Contains(expectedFragment, message, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("notepad", message, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("clipboard body", message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Simplified_chinese_failure_message_is_human_readable()
    {
        var message = SelectionFailurePresentation.From(
            SelectionTextReadStatus.NoSelection,
            CultureInfo.GetCultureInfo("zh-Hans"));

        Assert.Equal("请先在其他应用中选择文字，再重试。", message);
    }
}
