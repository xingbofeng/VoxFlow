using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Dialogs;

public partial class VoxFlowFormDialogWindow : Window, INotifyPropertyChanged
{
    private string primaryText = string.Empty;
    private string secondaryText = string.Empty;
    private bool optionValue;
    private double? ownerOpacity;

    public VoxFlowFormDialogWindow(
        Window? owner,
        string title,
        string primaryLabel,
        string? secondaryLabel = null,
        string? optionLabel = null,
        string? initialPrimary = null,
        string? initialSecondary = null,
        bool initialOption = false)
    {
        InitializeComponent();
        Owner = owner;
        TitleText = title;
        PrimaryLabel = primaryLabel;
        SecondaryLabel = secondaryLabel ?? string.Empty;
        OptionLabel = optionLabel ?? string.Empty;
        PrimaryText = initialPrimary ?? string.Empty;
        SecondaryText = initialSecondary ?? string.Empty;
        OptionValue = initialOption;
        CancelText = L10n.Localize("DialogCancel");
        ConfirmText = L10n.Localize("DialogConfirm");
        SecondaryPanel.Visibility = secondaryLabel is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        OptionCheckBox.Visibility = optionLabel is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        DataContext = this;
        Loaded += (_, _) =>
        {
            if (Owner is not null)
            {
                ownerOpacity = Owner.Opacity;
                Owner.Opacity = 0.72;
            }
            PrimaryTextBox.Focus();
            PrimaryTextBox.SelectAll();
        };
        Closed += (_, _) =>
        {
            if (Owner is not null && ownerOpacity is { } opacity)
            {
                Owner.Opacity = opacity;
            }
        };
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string TitleText { get; }

    public string PrimaryLabel { get; }

    public string SecondaryLabel { get; }

    public string OptionLabel { get; }

    public string CancelText { get; }

    public string ConfirmText { get; }

    public string PrimaryText
    {
        get => primaryText;
        set => SetField(ref primaryText, value);
    }

    public string SecondaryText
    {
        get => secondaryText;
        set => SetField(ref secondaryText, value);
    }

    public bool OptionValue
    {
        get => optionValue;
        set => SetField(ref optionValue, value);
    }

    private void OnConfirm(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(PrimaryText))
        {
            PrimaryTextBox.Focus();
            return;
        }

        PrimaryText = PrimaryText.Trim();
        SecondaryText = SecondaryText.Trim();
        DialogResult = true;
    }

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
