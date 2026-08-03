using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Resources;
using System.Text.RegularExpressions;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Tests;

public sealed partial class LocalizationResourceParityTests
{
    private static readonly CultureInfo[] LocalizedCultures =
    [
        CultureInfo.GetCultureInfo("zh-Hans"),
        CultureInfo.GetCultureInfo("zh-Hant"),
        CultureInfo.GetCultureInfo("ja"),
        CultureInfo.GetCultureInfo("ko"),
    ];

    [Fact]
    public void Every_supported_locale_defines_every_visible_resource()
    {
        var manager = new ResourceManager(
            "VoxFlow.Windows.App.Localization.Resources.Strings",
            typeof(L10n).Assembly);
        var invariant = ReadResources(manager, CultureInfo.InvariantCulture);

        Assert.NotEmpty(invariant);
        Assert.All(invariant, entry => Assert.NotEqual(entry.Key, entry.Value));
        foreach (var culture in LocalizedCultures)
        {
            var localized = ReadResources(manager, culture);
            Assert.Equal(invariant.Keys.Order(), localized.Keys.Order());
            foreach (var (key, englishValue) in invariant)
            {
                Assert.False(string.IsNullOrWhiteSpace(localized[key]), $"{culture.Name}: {key}");
                Assert.NotEqual(key, localized[key]);
                Assert.Equal(Placeholders(englishValue), Placeholders(localized[key]));
            }
        }
    }

    [Fact]
    public void Every_public_L10n_property_has_a_resource_in_every_supported_locale()
    {
        var manager = new ResourceManager(
            "VoxFlow.Windows.App.Localization.Resources.Strings",
            typeof(L10n).Assembly);
        var cultures = new[] { CultureInfo.InvariantCulture }.Concat(LocalizedCultures);
        var propertyNames = typeof(L10n)
            .GetProperties(BindingFlags.Public | BindingFlags.Static)
            .Where(property => property.PropertyType == typeof(string) && property.GetMethod is not null)
            .Select(property => property.Name)
            .Order()
            .ToArray();

        Assert.NotEmpty(propertyNames);
        foreach (var culture in cultures)
        {
            var resources = ReadResources(manager, culture);
            foreach (var propertyName in propertyNames)
            {
                Assert.True(
                    resources.ContainsKey(propertyName),
                    $"{(string.IsNullOrEmpty(culture.Name) ? "invariant" : culture.Name)}: {propertyName}");
            }
        }
    }

    [Fact]
    public void Visible_resources_are_not_raw_or_humanized_resource_keys_and_have_readable_fallbacks()
    {
        var manager = new ResourceManager(
            "VoxFlow.Windows.App.Localization.Resources.Strings",
            typeof(L10n).Assembly);
        var invariant = ReadResources(manager, CultureInfo.InvariantCulture);

        foreach (var (key, english) in invariant)
        {
            AssertReadableValue(key, english);
            var humanizedKey = HumanizeKey(key);
            Assert.False(
                string.Equals(Compact(english), Compact(humanizedKey), StringComparison.OrdinalIgnoreCase),
                $"English resource is a humanized key instead of a user-facing phrase: {key}");

            foreach (var culture in LocalizedCultures)
            {
                AssertReadableValue(key, ReadResources(manager, culture)[key]);
            }
        }
    }

    private static Dictionary<string, string> ReadResources(
        ResourceManager manager,
        CultureInfo culture)
    {
        var set = manager.GetResourceSet(culture, createIfNotExists: true, tryParents: false)
            ?? throw new MissingManifestResourceException(culture.Name);
        return set.Cast<DictionaryEntry>().ToDictionary(
            entry => Assert.IsType<string>(entry.Key),
            entry => Assert.IsType<string>(entry.Value));
    }

    private static string[] Placeholders(string value) => PlaceholderPattern()
        .Matches(value)
        .Select(match => match.Groups[1].Value)
        .Order()
        .ToArray();

    private static void AssertReadableValue(string key, string value)
    {
        Assert.False(string.IsNullOrWhiteSpace(value), key);
        Assert.False(string.Equals(key, value, StringComparison.OrdinalIgnoreCase), key);
        Assert.DoesNotContain('\uFFFD', value);
        Assert.DoesNotContain("???", value, StringComparison.Ordinal);
        Assert.DoesNotContain(key, value, StringComparison.Ordinal);
    }

    private static string HumanizeKey(string key) => KeyWordBoundary()
        .Replace(key, " ")
        .Replace('_', ' ')
        .Trim();

    private static string Compact(string value) => Whitespace()
        .Replace(value, string.Empty);

    [GeneratedRegex(@"\{(\d+)(?:[^}]*)\}", RegexOptions.CultureInvariant)]
    private static partial Regex PlaceholderPattern();

    [GeneratedRegex(@"(?<=[a-z0-9])(?=[A-Z])", RegexOptions.CultureInvariant)]
    private static partial Regex KeyWordBoundary();

    [GeneratedRegex(@"\s+", RegexOptions.CultureInvariant)]
    private static partial Regex Whitespace();
}
