using System.Collections;
using System.Globalization;
using System.Resources;
using System.Text.RegularExpressions;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Tests;

public sealed partial class LlmProviderLocalizationTests
{
    private static readonly CultureInfo[] Cultures =
    [
        CultureInfo.InvariantCulture,
        CultureInfo.GetCultureInfo("zh-Hans"),
        CultureInfo.GetCultureInfo("zh-Hant"),
        CultureInfo.GetCultureInfo("ja"),
        CultureInfo.GetCultureInfo("ko"),
    ];

    [Fact]
    public void All_five_locales_have_the_same_provider_keys_and_placeholders()
    {
        var manager = new ResourceManager(
            "VoxFlow.Windows.App.Localization.Resources.Strings",
            typeof(L10n).Assembly);
        var resourcesByCulture = Cultures.ToDictionary(
            culture => culture,
            culture => ReadProviderResources(manager, culture));
        var invariant = resourcesByCulture[CultureInfo.InvariantCulture];

        Assert.NotEmpty(invariant);
        foreach (var resources in resourcesByCulture.Values)
        {
            Assert.Equal(invariant.Keys.Order(), resources.Keys.Order());
            foreach (var (key, englishValue) in invariant)
            {
                var localized = resources[key];
                Assert.False(string.IsNullOrWhiteSpace(localized));
                Assert.NotEqual(key, localized);
                Assert.Equal(Placeholders(englishValue), Placeholders(localized));
            }
        }
    }

    private static Dictionary<string, string> ReadProviderResources(
        ResourceManager manager,
        CultureInfo culture)
    {
        var set = manager.GetResourceSet(culture, createIfNotExists: true, tryParents: false)
            ?? throw new MissingManifestResourceException(culture.Name);
        return set.Cast<DictionaryEntry>()
            .Where(entry => entry.Key is string key
                && key.StartsWith("LlmProvider", StringComparison.Ordinal))
            .ToDictionary(
                entry => (string)entry.Key,
                entry => Assert.IsType<string>(entry.Value));
    }

    private static string[] Placeholders(string value) => PlaceholderPattern()
        .Matches(value)
        .Select(match => match.Groups[1].Value)
        .Order()
        .ToArray();

    [GeneratedRegex(@"\{(\d+)(?:[^}]*)\}", RegexOptions.CultureInvariant)]
    private static partial Regex PlaceholderPattern();
}
