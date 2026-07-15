using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using WpfButton = System.Windows.Controls.Button;
using WpfTabControl = System.Windows.Controls.TabControl;
using WpfTabItem = System.Windows.Controls.TabItem;
using FormsScreen = System.Windows.Forms.Screen;

namespace VoxFlow.Windows.App.Screenshot;

public partial class ScreenshotDetailWindow : System.Windows.Window
{
    private ScreenshotDetailViewModel? attachedViewModel;

    public ScreenshotDetailWindow()
    {
        InitializeComponent();
        TrySetAppIcon();
    }

    public void PlaceOnOwnerScreen(Window? owner)
    {
        if (owner is not null)
        {
            Owner = owner;
        }

        var workArea = ResolveOwnerWorkArea(owner);
        ApplyResponsiveBounds(workArea);
    }

    public void ApplyResponsiveBounds(Rect workArea, double margin = 24)
    {
        var bounds = ScreenshotResponsiveWindowLayout.Centered(
            workArea,
            preferredWidth: 960,
            preferredHeight: 720,
            margin);
        MinWidth = Math.Min(360, bounds.Width);
        MinHeight = Math.Min(320, bounds.Height);
        Width = bounds.Width;
        Height = bounds.Height;
        Left = bounds.Left;
        Top = bounds.Top;
    }

    private ScreenshotDetailViewModel? ViewModel =>
        DataContext as ScreenshotDetailViewModel;

    private void OnLoaded(object sender, RoutedEventArgs eventArgs)
    {
        // Prefer the owner window's monitor; fall back only if placement was not set.
        if (Owner is null)
        {
            ApplyResponsiveBounds(SystemParameters.WorkArea);
        }
    }

    private void OnDataContextChanged(
        object sender,
        DependencyPropertyChangedEventArgs eventArgs)
    {
        if (attachedViewModel is not null)
        {
            attachedViewModel.CloseRequested -= OnCloseRequested;
        }
        attachedViewModel = eventArgs.NewValue as ScreenshotDetailViewModel;
        if (attachedViewModel is not null)
        {
            attachedViewModel.CloseRequested += OnCloseRequested;
        }
    }

    private void OnCloseRequested(object? sender, EventArgs eventArgs) => Close();

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.Escape)
        {
            eventArgs.Handled = true;
            Close();
        }
    }

    private void OnClose(object sender, RoutedEventArgs eventArgs) => Close();

    private void OnShowOriginal(object sender, RoutedEventArgs eventArgs) =>
        ViewModel?.ShowOriginal();

    private void OnShowTranslation(object sender, RoutedEventArgs eventArgs) =>
        ViewModel?.ShowTranslation();

    private void OnTextSectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        if (sender is not WpfTabControl
            { SelectedItem: WpfTabItem { Tag: string section } }
            || ViewModel is not { } viewModel
            || !Enum.TryParse<ScreenshotDetailTextSection>(
                section,
                ignoreCase: true,
                out var parsed))
        {
            return;
        }
        viewModel.SelectTextSection(parsed);
    }

    private async void OnAction(object sender, RoutedEventArgs eventArgs)
    {
        if (sender is WpfButton { Tag: string action }
            && ViewModel is { } viewModel)
        {
            await viewModel.ExecuteAsync(action);
        }
    }

    protected override void OnClosed(EventArgs eventArgs)
    {
        if (attachedViewModel is not null)
        {
            attachedViewModel.CloseRequested -= OnCloseRequested;
            attachedViewModel = null;
        }
        base.OnClosed(eventArgs);
    }

    private static Rect ResolveOwnerWorkArea(Window? owner)
    {
        try
        {
            if (owner is not null)
            {
                var handle = new WindowInteropHelper(owner).Handle;
                if (handle != IntPtr.Zero)
                {
                    var screen = FormsScreen.FromHandle(handle);
                    return DevicePixelsToDip(screen.WorkingArea, owner);
                }

                // Owner not yet presented: use its logical position as a hint.
                var point = new System.Drawing.Point(
                    (int)(owner.Left + (owner.Width / 2)),
                    (int)(owner.Top + (owner.Height / 2)));
                var screenFromPoint = FormsScreen.FromPoint(point);
                return DevicePixelsToDip(screenFromPoint.WorkingArea, owner);
            }
        }
        catch
        {
            // Fall through to primary work area.
        }

        return SystemParameters.WorkArea;
    }

    private static Rect DevicePixelsToDip(
        System.Drawing.Rectangle devicePixels,
        Visual relativeTo)
    {
        var source = PresentationSource.FromVisual(relativeTo);
        if (source?.CompositionTarget is null)
        {
            return new Rect(
                devicePixels.Left,
                devicePixels.Top,
                devicePixels.Width,
                devicePixels.Height);
        }

        var fromDevice = source.CompositionTarget.TransformFromDevice;
        var topLeft = fromDevice.Transform(
            new System.Windows.Point(devicePixels.Left, devicePixels.Top));
        var bottomRight = fromDevice.Transform(
            new System.Windows.Point(devicePixels.Right, devicePixels.Bottom));
        return new Rect(topLeft, bottomRight);
    }

    private void TrySetAppIcon()
    {
        try
        {
            Icon = BitmapFrame.Create(
                new Uri("pack://application:,,,/Assets/VoxFlow.png", UriKind.Absolute));
        }
        catch
        {
            // Icon is cosmetic; keep default if resource is missing.
        }
    }
}
