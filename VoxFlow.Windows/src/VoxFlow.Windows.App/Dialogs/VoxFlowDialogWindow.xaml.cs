using System.Windows;
using System.Windows.Media;
using VoxFlow.Windows.App.Localization;
using MediaBrush = System.Windows.Media.Brush;

namespace VoxFlow.Windows.App.Dialogs;

public enum VoxFlowDialogKind
{
    Information,
    Warning,
    Destructive,
}

public partial class VoxFlowDialogWindow : Window
{
    private double? ownerOpacity;

    private VoxFlowDialogWindow(
        string title,
        string message,
        string confirmLabel,
        string cancelLabel,
        bool showCancel,
        VoxFlowDialogKind kind)
    {
        InitializeComponent();
        DialogTitle = title;
        Message = message;
        ConfirmLabel = confirmLabel;
        CancelLabel = cancelLabel;
        CancelVisibility = showCancel ? Visibility.Visible : Visibility.Collapsed;
        (IconGlyph, IconForeground, IconBackground, ConfirmBackground) = kind switch
        {
            VoxFlowDialogKind.Destructive => (
                "\uE74D",
                Brush("#D14343"),
                Brush("#FDE8E8"),
                Brush("#C93B3B")),
            VoxFlowDialogKind.Warning => (
                "\uE7BA",
                Brush("#B77900"),
                Brush("#FFF4D6"),
                ApplicationBrush("AccentBrush", "#0F7A66")),
            _ => (
                "\uE946",
                ApplicationBrush("AccentBrush", "#0F7A66"),
                ApplicationBrush("AccentSoftBrush", "#DCECE7"),
                ApplicationBrush("AccentBrush", "#0F7A66")),
        };
        DataContext = this;
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    public string DialogTitle { get; }

    public string Message { get; }

    public string ConfirmLabel { get; }

    public string CancelLabel { get; }

    public Visibility CancelVisibility { get; }

    public string IconGlyph { get; }

    public MediaBrush IconForeground { get; }

    public MediaBrush IconBackground { get; }

    public MediaBrush ConfirmBackground { get; }

    public static bool ShowConfirm(
        Window? owner,
        string title,
        string message,
        string? confirmLabel = null,
        VoxFlowDialogKind kind = VoxFlowDialogKind.Destructive)
    {
        var dialog = Create(
            owner,
            title,
            message,
            confirmLabel ?? L10n.Localize("DialogConfirm"),
            L10n.Localize("DialogCancel"),
            showCancel: true,
            kind);
        return dialog.ShowDialog() == true;
    }

    public static void ShowMessage(
        Window? owner,
        string title,
        string message,
        VoxFlowDialogKind kind = VoxFlowDialogKind.Information)
    {
        var dialog = Create(
            owner,
            title,
            message,
            L10n.Localize("DialogClose"),
            string.Empty,
            showCancel: false,
            kind);
        _ = dialog.ShowDialog();
    }

    private static VoxFlowDialogWindow Create(
        Window? owner,
        string title,
        string message,
        string confirmLabel,
        string cancelLabel,
        bool showCancel,
        VoxFlowDialogKind kind)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        ArgumentException.ThrowIfNullOrWhiteSpace(message);
        var dialog = new VoxFlowDialogWindow(
            title,
            message,
            confirmLabel,
            cancelLabel,
            showCancel,
            kind);
        var resolvedOwner = owner ?? System.Windows.Application.Current?.MainWindow;
        if (resolvedOwner is { IsLoaded: true } && !ReferenceEquals(resolvedOwner, dialog))
        {
            dialog.Owner = resolvedOwner;
        }
        else
        {
            dialog.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }
        return dialog;
    }

    private static SolidColorBrush Brush(string color) =>
        new((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));

    private static MediaBrush ApplicationBrush(string key, string fallback) =>
        System.Windows.Application.Current?.TryFindResource(key) as MediaBrush ?? Brush(fallback);

    private void OnConfirm(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
        Close();
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (Owner is not null)
        {
            ownerOpacity = Owner.Opacity;
            Owner.Opacity = 0.72;
        }
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        if (Owner is not null && ownerOpacity is { } opacity)
        {
            Owner.Opacity = opacity;
        }
        Loaded -= OnLoaded;
        Closed -= OnClosed;
    }
}
