using System.Windows;
using System.Windows.Input;
using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Settings;

public partial class InteractiveHotkeyRowView : System.Windows.Controls.UserControl
{
    public InteractiveHotkeyRowView() => InitializeComponent();

    private InteractiveHotkeyRowViewModel? ViewModel =>
        DataContext as InteractiveHotkeyRowViewModel;

    private void OnRecordClick(object sender, RoutedEventArgs e)
    {
        ViewModel?.BeginRecording();
        Focus();
        Keyboard.Focus(this);
    }

    private void OnCancelClick(object sender, RoutedEventArgs e) =>
        ViewModel?.CancelRecording();

    private async void OnClearClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.ClearAsync(CancellationToken.None);
        }
    }

    private async void OnRestoreDefaultClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel is { } viewModel)
        {
            await viewModel.RestoreDefaultAsync(CancellationToken.None);
        }
    }

    private async void OnPreviewKeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        if (ViewModel is not { IsRecording: true } viewModel)
        {
            return;
        }

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (viewModel.Action == InteractiveHotkeyAction.Dictation
            && key == Key.RightCtrl)
        {
            await viewModel.ApplyCapturedBindingAsync(
                HotkeyBinding.RightControlDefault,
                CancellationToken.None);
            e.Handled = true;
            return;
        }
        if (IsModifier(key))
        {
            e.Handled = true;
            return;
        }
        if (Keyboard.IsKeyDown(Key.RightAlt))
        {
            viewModel.RejectAltGrCapture();
            e.Handled = true;
            return;
        }

        var virtualKey = checked((uint)KeyInterop.VirtualKeyFromKey(key));
        await viewModel.ApplyCapturedBindingAsync(
            WindowsHotkeyBindingCapture.Create(
                virtualKey,
                ReadModifiers(),
                IsExtended(key)),
            CancellationToken.None);
        e.Handled = true;
    }

    private static HotkeyModifiers ReadModifiers()
    {
        var keyboard = Keyboard.Modifiers;
        var value = HotkeyModifiers.None;
        if (keyboard.HasFlag(ModifierKeys.Control)) value |= HotkeyModifiers.Control;
        if (keyboard.HasFlag(ModifierKeys.Shift)) value |= HotkeyModifiers.Shift;
        if (keyboard.HasFlag(ModifierKeys.Alt)) value |= HotkeyModifiers.Alt;
        if (keyboard.HasFlag(ModifierKeys.Windows)) value |= HotkeyModifiers.Windows;
        return value;
    }

    private static bool IsModifier(Key key) => key is
        Key.LeftCtrl or Key.RightCtrl or
        Key.LeftShift or Key.RightShift or
        Key.LeftAlt or Key.RightAlt or
        Key.LWin or Key.RWin;

    private static bool IsExtended(Key key) => key is
        Key.RightCtrl or Key.RightAlt or Key.Insert or Key.Delete or
        Key.Home or Key.End or Key.PageUp or Key.PageDown or
        Key.Left or Key.Right or Key.Up or Key.Down;
}
