using VoxFlow.Windows.Platform.Selection;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class WindowsSelectionCopySenderTests
{
    [Fact]
    public void Copy_sender_implements_the_selection_transaction_boundary()
    {
        Assert.IsAssignableFrom<ISelectionCopySender>(new WindowsSelectionCopySender());
    }
}
