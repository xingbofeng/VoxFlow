using System.Windows;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.AgentWorkspace;

public partial class AgentWorkspaceView : System.Windows.Controls.UserControl
{
    public AgentWorkspaceView() => InitializeComponent();

    private void OnRefresh(object sender, RoutedEventArgs e) =>
        (DataContext as AgentWorkspacePageViewModel)?.Refresh();

    private void OnCopy(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is string id)
        {
            _ = (DataContext as AgentWorkspacePageViewModel)?.Copy(id);
        }
    }
}
