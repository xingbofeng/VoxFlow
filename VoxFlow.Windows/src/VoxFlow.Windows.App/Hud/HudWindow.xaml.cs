using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace VoxFlow.Windows.App.Hud;

public partial class HudWindow : Window
{
    private const int GwlExStyle = -20;
    private const int SwShowNoActivate = 4;

    public const int WsExTransparent = 0x00000020;
    public const int WsExToolWindow = 0x00000080;
    public const int WsExNoActivate = 0x08000000;
    public const int RequiredExtendedWindowStyles =
        WsExTransparent | WsExToolWindow | WsExNoActivate;

    public static readonly TimeSpan EntryAnimationDuration = TimeSpan.FromMilliseconds(350);
    public static readonly TimeSpan ExitAnimationDuration = TimeSpan.FromMilliseconds(220);

    private readonly HudWindowViewModel viewModel = new();
    private readonly DispatcherTimer dismissTimer;
    private bool isClosing;

    public HudWindow()
    {
        InitializeComponent();
        DataContext = viewModel;
        dismissTimer = new DispatcherTimer(DispatcherPriority.Normal, Dispatcher)
        {
            IsEnabled = false,
        };
        dismissTimer.Tick += OnDismissTimerTick;
        Loaded += OnLoaded;
    }

    public void ApplyPlacement(double left, double top, double width, double height)
    {
        if (!double.IsFinite(left)
            || !double.IsFinite(top)
            || !double.IsFinite(width)
            || !double.IsFinite(height)
            || width <= 0
            || height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        Left = left;
        Top = top;
        Width = width;
        Height = Math.Clamp(height, MinHeight, MaxHeight);
    }

    public void UpdatePresentation(HudPresentationSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        dismissTimer.Stop();
        viewModel.Update(snapshot);

        if (!snapshot.IsVisible)
        {
            BeginExitAnimation();
            return;
        }

        ShowWithoutActivation();
        BeginEntryAnimation();
        if (snapshot.AutoDismissAfter is { } delay)
        {
            dismissTimer.Interval = delay;
            dismissTimer.Start();
        }
    }

    public void SetCapsLockIndicatorEnabled(bool enabled) =>
        viewModel.SetCapsLockIndicatorEnabled(enabled);

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var handle = new WindowInteropHelper(this).Handle;
        var extendedStyles = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        _ = SetWindowLongPtr(
            handle,
            GwlExStyle,
            new nint(extendedStyles | RequiredExtendedWindowStyles));
    }

    protected override void OnClosed(EventArgs e)
    {
        isClosing = true;
        dismissTimer.Stop();
        dismissTimer.Tick -= OnDismissTimerTick;
        base.OnClosed(e);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var spinnerAnimation = new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(850))
        {
            RepeatBehavior = RepeatBehavior.Forever,
        };
        SpinnerRotation.BeginAnimation(
            System.Windows.Media.RotateTransform.AngleProperty,
            spinnerAnimation);
    }

    private void ShowWithoutActivation()
    {
        if (!IsVisible)
        {
            Show();
        }

        var handle = new WindowInteropHelper(this).Handle;
        if (handle != nint.Zero)
        {
            _ = ShowWindow(handle, SwShowNoActivate);
        }
    }

    private void BeginEntryAnimation()
    {
        BeginAnimation(OpacityProperty, null);
        CapsuleTranslate.BeginAnimation(
            System.Windows.Media.TranslateTransform.YProperty,
            null);
        CapsuleScale.BeginAnimation(
            System.Windows.Media.ScaleTransform.ScaleXProperty,
            null);
        CapsuleScale.BeginAnimation(
            System.Windows.Media.ScaleTransform.ScaleYProperty,
            null);

        Opacity = 0;
        CapsuleTranslate.Y = 14;
        CapsuleScale.ScaleX = 0.97;
        CapsuleScale.ScaleY = 0.97;
        var easing = new BackEase
        {
            Amplitude = 0.22,
            EasingMode = EasingMode.EaseOut,
        };
        BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(1, EntryAnimationDuration) { EasingFunction = easing });
        CapsuleTranslate.BeginAnimation(
            System.Windows.Media.TranslateTransform.YProperty,
            new DoubleAnimation(0, EntryAnimationDuration) { EasingFunction = easing });
        CapsuleScale.BeginAnimation(
            System.Windows.Media.ScaleTransform.ScaleXProperty,
            new DoubleAnimation(1, EntryAnimationDuration) { EasingFunction = easing });
        CapsuleScale.BeginAnimation(
            System.Windows.Media.ScaleTransform.ScaleYProperty,
            new DoubleAnimation(1, EntryAnimationDuration) { EasingFunction = easing });
    }

    private void BeginExitAnimation()
    {
        dismissTimer.Stop();
        if (!IsVisible || isClosing)
        {
            return;
        }

        var animation = new DoubleAnimation(0, ExitAnimationDuration)
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn },
        };
        animation.Completed += (_, _) =>
        {
            if (!isClosing)
            {
                Hide();
            }
        };
        BeginAnimation(OpacityProperty, animation);
        CapsuleTranslate.BeginAnimation(
            System.Windows.Media.TranslateTransform.YProperty,
            new DoubleAnimation(9, ExitAnimationDuration));
    }

    private void OnDismissTimerTick(object? sender, EventArgs e) => BeginExitAnimation();

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint windowHandle, int index, nint newValue);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(nint windowHandle, int command);
}
