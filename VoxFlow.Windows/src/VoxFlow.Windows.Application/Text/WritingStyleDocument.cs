namespace VoxFlow.Windows.Application.Text;

public sealed record WritingStyleProfile(
    Guid Id,
    string Name,
    string Description,
    string Instruction,
    string MarkdownTemplate,
    IReadOnlyList<string> ApplicationRoutes,
    bool IsBuiltIn = false,
    bool AiAutoMatchEnabled = true)
{
    public WritingStyleProfile Normalize() => this with
    {
        Name = Name.Trim(),
        Description = Description.Trim(),
        Instruction = Instruction.Trim(),
        MarkdownTemplate = MarkdownTemplate.Trim(),
        ApplicationRoutes = ApplicationRoutes
            .Select(value => value.Trim())
            .Where(value => value.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray(),
    };
}

public sealed record WritingStyleDocument(
    IReadOnlyList<WritingStyleProfile> Profiles,
    Guid? SelectedProfileId,
    bool AiAutoMatch,
    int SchemaVersion = 1)
{
    public const int CurrentSchemaVersion = 1;

    public static readonly Guid GeneralProfileId =
        Guid.Parse("728fa2d1-15f5-45bb-9050-3c836a83b80e");
    public static readonly Guid WritingProfileId =
        Guid.Parse("80db867d-62fd-4992-b3e0-b84afe3328fd");
    public static readonly Guid CodingProfileId =
        Guid.Parse("b6a6f287-e33d-4cbc-b72f-d69aa78b4c10");
    public static readonly Guid SocialProfileId =
        Guid.Parse("01253e20-6ee9-4394-b5d2-9951ad216e7e");
    public static readonly Guid EmailProfileId =
        Guid.Parse("3f8c1d2a-6b7e-4a91-9c0d-1e2f3a4b5c6d");
    public static readonly Guid MeetingProfileId =
        Guid.Parse("4a9d2e3b-7c8f-5b02-ad1e-2f3a4b5c6d7e");
    public static readonly Guid TranslationProfileId =
        Guid.Parse("5b0e3f4c-8d90-6c13-be2f-3a4b5c6d7e8f");

    public static IReadOnlyList<WritingStyleProfile> BuiltInCatalog { get; } = CreateBuiltInCatalog();

    public static WritingStyleDocument Default { get; } = new(
        BuiltInCatalog,
        GeneralProfileId,
        false,
        CurrentSchemaVersion);

    private static WritingStyleProfile[] CreateBuiltInCatalog() =>
    [
        new(
            GeneralProfileId,
            "General",
            "Natural, concise wording for everyday input.",
            "Keep the original tone. Prefer concise, natural sentences and conservative corrections.",
            string.Empty,
            [],
            true,
            true),
        new(
            WritingProfileId,
            "Writing",
            "Polished prose with clear paragraph structure.",
            "Polish the wording while preserving all facts and intent. Use clear paragraphs and avoid filler.",
            string.Empty,
            ["Word", "Notepad"],
            true,
            true),
        new(
            CodingProfileId,
            "Coding",
            "Preserve symbols, identifiers, paths, and technical vocabulary.",
            "Treat the input as technical content. Preserve identifiers, commands, code, paths, versions, and Markdown exactly unless an ASR error is obvious.",
            "```text\n{{content}}\n```",
            ["Visual Studio", "Code", "Terminal", "PowerShell"],
            true,
            true),
        new(
            SocialProfileId,
            "Social",
            "Short, friendly wording for chat and social apps.",
            "Keep the message friendly and conversational. Prefer short sentences and preserve the user's voice.",
            string.Empty,
            ["WeChat", "Slack", "Teams", "Discord"],
            true,
            true),
        new(
            EmailProfileId,
            "Email",
            "Clear professional email tone with a greeting and sign-off when appropriate.",
            "Rewrite as a clear professional email. Keep all facts, names, dates, and requests. Prefer short paragraphs.",
            "## Email\n\n{{content}}",
            ["Outlook", "Mail", "Gmail", "Thunderbird"],
            true,
            true),
        new(
            MeetingProfileId,
            "Meeting",
            "Concise meeting notes with action-oriented wording.",
            "Turn dictation into concise meeting notes. Prefer bullets for decisions and action items. Preserve names and deadlines.",
            "### Notes\n\n{{content}}",
            ["Zoom", "Teams", "Meet", "Webex"],
            true,
            true),
        new(
            TranslationProfileId,
            "Translation",
            "Preserve meaning for bilingual or translation-oriented cleanup.",
            "Clean speech-recognition noise while preserving the source language and meaning. Do not translate unless the user already mixed languages.",
            string.Empty,
            [],
            true,
            true),
    ];

    public WritingStyleDocument Normalize()
    {
        var byId = Profiles
            .Select(profile => profile.Normalize())
            .Where(profile => profile.Name.Length > 0)
            .GroupBy(profile => profile.Id)
            .Select(group => group.First())
            .ToDictionary(profile => profile.Id);

        // Ensure built-ins always exist and stay marked built-in (protection).
        foreach (var builtIn in BuiltInCatalog)
        {
            if (byId.TryGetValue(builtIn.Id, out var existing))
            {
                byId[builtIn.Id] = existing with
                {
                    IsBuiltIn = true,
                    Name = existing.Name.Length > 0 ? existing.Name : builtIn.Name,
                };
            }
            else
            {
                byId[builtIn.Id] = builtIn;
            }
        }

        var profiles = BuiltInCatalog
            .Select(builtIn => byId[builtIn.Id])
            .Concat(byId.Values.Where(profile => !profile.IsBuiltIn))
            .ToArray();

        var selected = SelectedProfileId is { } selectedId
            && profiles.Any(profile => profile.Id == selectedId)
                ? selectedId
                : profiles.FirstOrDefault()?.Id;
        return this with
        {
            Profiles = profiles,
            SelectedProfileId = selected,
            SchemaVersion = CurrentSchemaVersion,
        };
    }

    public WritingStyleProfile? SelectedProfile => SelectedProfileId is { } id
        ? Profiles.FirstOrDefault(profile => profile.Id == id)
        : null;

    /// <summary>
    /// Profiles eligible for AI auto-match when document-level auto-match is on.
    /// </summary>
    public IReadOnlyList<WritingStyleProfile> AiMatchCandidates => Profiles
        .Where(profile => profile.AiAutoMatchEnabled)
        .ToArray();
}

public interface IWritingStyleStore
{
    ValueTask<WritingStyleDocument> LoadAsync(CancellationToken cancellationToken);

    ValueTask SaveAsync(
        WritingStyleDocument document,
        CancellationToken cancellationToken);
}

public sealed record WritingStyleApplicationContext(
    string ProcessPath,
    string WindowTitle)
{
    public string ProcessName => Path.GetFileNameWithoutExtension(ProcessPath);

    public bool Matches(string route)
    {
        ArgumentNullException.ThrowIfNull(route);
        var candidate = route.Trim();
        return candidate.Length > 0
            && (ProcessName.Contains(candidate, StringComparison.OrdinalIgnoreCase)
                || ProcessPath.Contains(candidate, StringComparison.OrdinalIgnoreCase)
                || WindowTitle.Contains(candidate, StringComparison.OrdinalIgnoreCase));
    }
}
