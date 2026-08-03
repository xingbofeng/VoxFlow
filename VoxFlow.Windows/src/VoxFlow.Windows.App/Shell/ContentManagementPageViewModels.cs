using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.App.Shell;

public sealed class GlossaryPageViewModel : BindableObject
{
    private readonly IGlossaryStore store;
    private readonly IGlossarySuggestionSource? suggestionSource;
    private GlossaryDocument document = GlossaryDocument.Default;
    private string searchText = string.Empty;
    private string? feedbackMessage;

    public GlossaryPageViewModel(
        IGlossaryStore store,
        IGlossarySuggestionSource? suggestionSource = null)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.suggestionSource = suggestionSource;
        HotwordsView = CollectionViewSource.GetDefaultView(Hotwords);
        HotwordsView.Filter = FilterHotword;
        ReplacementsView = CollectionViewSource.GetDefaultView(Replacements);
        ReplacementsView.Filter = FilterReplacement;
    }

    public string Heading => L10n.Localize("GlossaryHeading");

    public string Subtitle => L10n.Localize("GlossarySubtitle");

    public ObservableCollection<GlossaryHotword> Hotwords { get; } = [];

    public ObservableCollection<TextReplacementRule> Replacements { get; } = [];

    public ObservableCollection<string> Suggestions { get; } = [];

    public ICollectionView HotwordsView { get; }

    public ICollectionView ReplacementsView { get; }

    public string SearchText
    {
        get => searchText;
        set
        {
            if (SetField(ref searchText, value))
            {
                HotwordsView.Refresh();
                ReplacementsView.Refresh();
            }
        }
    }

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        document = await store.LoadAsync(cancellationToken).ConfigureAwait(true);
        RefreshCollections();
    }

    public async Task AddHotwordAsync(
        string term,
        string? note,
        CancellationToken cancellationToken = default)
    {
        var existing = Hotwords.FirstOrDefault(item =>
            string.Equals(item.Term, term.Trim(), StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            FeedbackMessage = L10n.Localize("GlossaryDuplicateMessage");
            return;
        }

        Hotwords.Add(new GlossaryHotword(Guid.NewGuid(), term.Trim(), note));
        await SaveAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task AddReplacementAsync(
        string source,
        string target,
        bool wholeWord,
        CancellationToken cancellationToken = default)
    {
        var normalized = source.Trim();
        var existing = Replacements.FirstOrDefault(item =>
            string.Equals(item.Source, normalized, StringComparison.Ordinal));
        if (existing is not null)
        {
            Replacements.Remove(existing);
        }
        Replacements.Add(new TextReplacementRule(
            Guid.NewGuid(),
            normalized,
            target.Trim(),
            true,
            wholeWord));
        await SaveAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task RemoveHotwordAsync(
        GlossaryHotword item,
        CancellationToken cancellationToken = default)
    {
        Hotwords.Remove(item);
        await SaveAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task RemoveReplacementAsync(
        TextReplacementRule item,
        CancellationToken cancellationToken = default)
    {
        Replacements.Remove(item);
        await SaveAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task AddSuggestionAsync(
        string term,
        CancellationToken cancellationToken = default)
    {
        await AddHotwordAsync(term, null, cancellationToken).ConfigureAwait(true);
        Suggestions.Remove(term);
    }

    public async Task IgnoreSuggestionAsync(
        string term,
        CancellationToken cancellationToken = default)
    {
        document = document with
        {
            IgnoredSuggestions = [.. document.IgnoredSuggestions, term],
        };
        Suggestions.Remove(term);
        await SaveAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task<int> ImportHotwordsAsync(
        IEnumerable<string> lines,
        CancellationToken cancellationToken = default)
    {
        var before = Hotwords.Count;
        foreach (var term in lines.Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#'))
            .Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!Hotwords.Any(item =>
                string.Equals(item.Term, term, StringComparison.OrdinalIgnoreCase)))
            {
                Hotwords.Add(new GlossaryHotword(Guid.NewGuid(), term));
            }
        }
        await SaveAsync(cancellationToken).ConfigureAwait(true);
        return Hotwords.Count - before;
    }

    public GlossaryDocument Snapshot() => BuildDocument();

    private async Task SaveAsync(CancellationToken cancellationToken)
    {
        document = BuildDocument().Normalize();
        await store.SaveAsync(document, cancellationToken).ConfigureAwait(true);
        FeedbackMessage = L10n.Localize("GlossarySavedMessage");
        RefreshSuggestions();
        HotwordsView.Refresh();
        ReplacementsView.Refresh();
    }

    private GlossaryDocument BuildDocument() => new(
        Hotwords.ToArray(),
        Replacements.ToArray(),
        document.IgnoredSuggestions,
        GlossaryDocument.CurrentSchemaVersion);

    private void RefreshCollections()
    {
        Hotwords.Clear();
        foreach (var item in document.Hotwords)
        {
            Hotwords.Add(item);
        }
        Replacements.Clear();
        foreach (var item in document.Replacements)
        {
            Replacements.Add(item);
        }
        RefreshSuggestions();
        HotwordsView.Refresh();
        ReplacementsView.Refresh();
    }

    private void RefreshSuggestions()
    {
        Suggestions.Clear();
        foreach (var term in (suggestionSource?.ReadSuggestions() ?? []).Where(term =>
            !Hotwords.Any(item => string.Equals(item.Term, term, StringComparison.OrdinalIgnoreCase))
            && !document.IgnoredSuggestions.Contains(term, StringComparer.OrdinalIgnoreCase)))
        {
            Suggestions.Add(term);
        }
    }

    private bool FilterHotword(object value) => value is GlossaryHotword item
        && (SearchText.Length == 0
            || item.Term.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase)
            || (item.Note?.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase) ?? false));

    private bool FilterReplacement(object value) => value is TextReplacementRule item
        && (SearchText.Length == 0
            || item.Source.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase)
            || item.Target.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase));
}

public sealed class WritingStyleEditorViewModel : BindableObject
{
    private string name;
    private string description;
    private string instruction;
    private string markdownTemplate;
    private string applicationRoutes;
    private bool aiAutoMatchEnabled;

    public WritingStyleEditorViewModel(WritingStyleProfile profile)
    {
        Id = profile.Id;
        (name, description) = profile.IsBuiltIn
            ? BuiltInPresentation(profile)
            : (profile.Name, profile.Description);
        instruction = profile.Instruction;
        markdownTemplate = profile.MarkdownTemplate;
        applicationRoutes = string.Join(", ", profile.ApplicationRoutes);
        aiAutoMatchEnabled = profile.AiAutoMatchEnabled;
        IsBuiltIn = profile.IsBuiltIn;
    }

    public Guid Id { get; }

    public bool IsBuiltIn { get; }

    public bool CanDelete => !IsBuiltIn;

    public string Name
    {
        get => name;
        set
        {
            if (IsBuiltIn)
            {
                return;
            }

            SetField(ref name, value);
        }
    }

    public string Description
    {
        get => description;
        set
        {
            if (IsBuiltIn)
            {
                return;
            }

            SetField(ref description, value);
        }
    }

    public string Instruction
    {
        get => instruction;
        set
        {
            if (SetField(ref instruction, value))
            {
                OnPropertyChanged(nameof(PreviewText));
            }
        }
    }

    public string MarkdownTemplate
    {
        get => markdownTemplate;
        set
        {
            if (SetField(ref markdownTemplate, value))
            {
                OnPropertyChanged(nameof(PreviewText));
            }
        }
    }

    public string ApplicationRoutes { get => applicationRoutes; set => SetField(ref applicationRoutes, value); }

    public bool AiAutoMatchEnabled
    {
        get => aiAutoMatchEnabled;
        set => SetField(ref aiAutoMatchEnabled, value);
    }

    public string RoutesSummary => string.IsNullOrWhiteSpace(applicationRoutes)
        ? L10n.Localize("WritingStylesRoutesEmpty")
        : applicationRoutes;

    /// <summary>Structured Markdown preview (not raw source echo).</summary>
    public string PreviewText
    {
        get
        {
            var rendered = MarkdownPreviewModel.RenderStructuredText(
                markdownTemplate,
                L10n.Localize("WritingStylesPreviewSample"));
            return string.IsNullOrWhiteSpace(rendered)
                ? L10n.Localize("WritingStylesPreviewEmpty")
                : rendered;
        }
    }

    public WritingStyleProfile ToProfile() => new WritingStyleProfile(
        Id,
        Name,
        Description,
        Instruction,
        MarkdownTemplate,
        ApplicationRoutes.Split([',', ';', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries),
        IsBuiltIn,
        AiAutoMatchEnabled).Normalize();

    private static (string Name, string Description) BuiltInPresentation(
        WritingStyleProfile profile) => profile.Id switch
    {
        var id when id == WritingStyleDocument.GeneralProfileId => (
            L10n.Localize("WritingStyleGeneralName"),
            L10n.Localize("WritingStyleGeneralDescription")),
        var id when id == WritingStyleDocument.WritingProfileId => (
            L10n.Localize("WritingStyleWritingName"),
            L10n.Localize("WritingStyleWritingDescription")),
        var id when id == WritingStyleDocument.CodingProfileId => (
            L10n.Localize("WritingStyleCodingName"),
            L10n.Localize("WritingStyleCodingDescription")),
        var id when id == WritingStyleDocument.SocialProfileId => (
            L10n.Localize("WritingStyleSocialName"),
            L10n.Localize("WritingStyleSocialDescription")),
        var id when id == WritingStyleDocument.EmailProfileId => (
            L10n.Localize("WritingStyleEmailName"),
            L10n.Localize("WritingStyleEmailDescription")),
        var id when id == WritingStyleDocument.MeetingProfileId => (
            L10n.Localize("WritingStyleMeetingName"),
            L10n.Localize("WritingStyleMeetingDescription")),
        var id when id == WritingStyleDocument.TranslationProfileId => (
            L10n.Localize("WritingStyleTranslationName"),
            L10n.Localize("WritingStyleTranslationDescription")),
        _ => (profile.Name, profile.Description),
    };
}

public sealed class WritingStylesPageViewModel : BindableObject
{
    private readonly IWritingStyleStore store;
    private WritingStyleDocument document = WritingStyleDocument.Default;
    private WritingStyleEditorViewModel? selectedProfile;
    private bool aiAutoMatch;
    private string? feedbackMessage;

    public WritingStylesPageViewModel(IWritingStyleStore store)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
    }

    public string Heading => L10n.Localize("WritingStylesHeading");

    public string Subtitle => L10n.Localize("WritingStylesSubtitle");

    public ObservableCollection<WritingStyleEditorViewModel> Profiles { get; } = [];

    public WritingStyleEditorViewModel? SelectedProfile
    {
        get => selectedProfile;
        set => SetField(ref selectedProfile, value);
    }

    public bool AiAutoMatch
    {
        get => aiAutoMatch;
        set => SetField(ref aiAutoMatch, value);
    }

    public string? FeedbackMessage
    {
        get => feedbackMessage;
        private set => SetField(ref feedbackMessage, value);
    }

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        document = await store.LoadAsync(cancellationToken).ConfigureAwait(true);
        Populate(document);
    }

    public void AddProfile(string name)
    {
        var editor = new WritingStyleEditorViewModel(new WritingStyleProfile(
            Guid.NewGuid(),
            name.Trim(),
            L10n.Localize("WritingStylesCustomDescription"),
            string.Empty,
            string.Empty,
            [],
            false,
            true));
        Profiles.Add(editor);
        SelectedProfile = editor;
    }

    public async Task DeleteSelectedAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedProfile is null || SelectedProfile.IsBuiltIn)
        {
            FeedbackMessage = L10n.Localize("WritingStylesBuiltInProtectedMessage");
            return;
        }

        Profiles.Remove(SelectedProfile);
        SelectedProfile = Profiles.FirstOrDefault();
        await SaveAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task SaveAsync(CancellationToken cancellationToken = default)
    {
        var profiles = Profiles
            .Select(editor => editor.ToProfile())
            .Where(profile => profile.Name.Length > 0)
            .ToArray();
        document = new WritingStyleDocument(
            profiles,
            SelectedProfile?.Id,
            AiAutoMatch,
            WritingStyleDocument.CurrentSchemaVersion).Normalize();
        await store.SaveAsync(document, cancellationToken).ConfigureAwait(true);
        Populate(document);
        FeedbackMessage = L10n.Localize("WritingStylesSavedMessage");
    }

    public async Task RestoreDefaultsAsync(CancellationToken cancellationToken = default)
    {
        document = WritingStyleDocument.Default;
        await store.SaveAsync(document, cancellationToken).ConfigureAwait(true);
        Populate(document);
        FeedbackMessage = L10n.Localize("WritingStylesRestoredMessage");
    }

    private void Populate(WritingStyleDocument value)
    {
        Profiles.Clear();
        foreach (var profile in value.Profiles)
        {
            Profiles.Add(new WritingStyleEditorViewModel(profile));
        }
        AiAutoMatch = value.AiAutoMatch;
        SelectedProfile = Profiles.FirstOrDefault(item => item.Id == value.SelectedProfileId)
            ?? Profiles.FirstOrDefault();
    }
}
