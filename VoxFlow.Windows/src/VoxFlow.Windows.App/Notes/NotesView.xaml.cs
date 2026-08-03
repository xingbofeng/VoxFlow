using System.Windows;
using VoxFlow.Windows.App.Shell;

namespace VoxFlow.Windows.App.Notes;

public partial class NotesView : System.Windows.Controls.UserControl
{
    public NotesView() => InitializeComponent();

    private void OnRefresh(object sender, RoutedEventArgs e) =>
        (DataContext as NotesPageViewModel)?.Refresh();

    private void OnCopy(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is string id)
        {
            _ = (DataContext as NotesPageViewModel)?.Copy(id);
        }
    }
}
