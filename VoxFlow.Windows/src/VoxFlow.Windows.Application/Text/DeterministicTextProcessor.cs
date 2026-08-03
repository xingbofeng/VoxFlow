using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace VoxFlow.Windows.Application.Text;

public static partial class DeterministicTextProcessor
{
    private static readonly IReadOnlyDictionary<char, int> ChineseDigits =
        new Dictionary<char, int>
        {
            ['零'] = 0,
            ['〇'] = 0,
            ['一'] = 1,
            ['二'] = 2,
            ['两'] = 2,
            ['三'] = 3,
            ['四'] = 4,
            ['五'] = 5,
            ['六'] = 6,
            ['七'] = 7,
            ['八'] = 8,
            ['九'] = 9,
        };

    public static string Process(
        string text,
        DeterministicTextProcessingSettings settings,
        bool isCodingContext = false)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(settings);
        if (!settings.Enabled)
        {
            return text;
        }

        var result = text;
        if (settings.FillerWordFiltering)
        {
            result = FilterFillers(result, isCodingContext);
        }

        if (settings.SmartNumberRecognition)
        {
            result = NormalizeSmartNumbers(result);
        }

        if (settings.PunctuationOptimization)
        {
            result = OptimizePunctuation(
                result,
                settings.PunctuationCjkThreshold,
                settings.PunctuationWordThreshold);
        }

        if (settings.CjkLatinSpacing)
        {
            result = AddCjkLatinSpacing(result);
        }

        if (settings.LongSentenceBreaking)
        {
            result = BreakLongSentences(
                result,
                settings.LongSentenceWordThreshold,
                settings.LongSentenceCjkThreshold);
        }

        if (settings.AutoCapitalization && !isCodingContext)
        {
            result = CapitalizeNaturalLines(result);
        }

        return result;
    }

    private static string FilterFillers(string text, bool isCodingContext)
    {
        var result = CjkFillerRegex().Replace(text, string.Empty);
        if (!isCodingContext)
        {
            result = LatinFillerRegex().Replace(result, string.Empty);
        }

        return RepeatedWhitespaceRegex()
            .Replace(result, " ")
            .Trim();
    }

    private static string NormalizeSmartNumbers(string text)
    {
        var result = ChineseYearRegex().Replace(text, match =>
        {
            var digits = new StringBuilder();
            foreach (var character in match.Groups[1].Value)
            {
                if (!ChineseDigits.TryGetValue(character, out var digit))
                {
                    return match.Value;
                }

                digits.Append(digit.ToString(CultureInfo.InvariantCulture));
            }

            return $"{digits}年";
        });
        result = ChinesePercentRegex().Replace(result, match =>
            TryParseChineseInteger(match.Groups[1].Value, out var value)
                ? $"{value.ToString(CultureInfo.InvariantCulture)}%"
                : match.Value);
        result = ChineseMonthRegex().Replace(result, match =>
            FormatChineseNumberWithSuffix(match, "月"));
        result = ChineseDayRegex().Replace(result, match =>
            FormatChineseNumberWithSuffix(match, "日"));
        result = ChineseHourRegex().Replace(result, match =>
            FormatChineseNumberWithSuffix(match, "点"));
        result = ChineseMinuteRegex().Replace(result, match =>
            FormatChineseNumberWithSuffix(match, "分"));
        result = ChineseQuantityRegex().Replace(result, match =>
            TryParseChineseInteger(match.Groups[1].Value, out var value)
                ? value.ToString(CultureInfo.InvariantCulture) + match.Groups[2].Value
                : match.Value);
        return result;
    }

    private static string FormatChineseNumberWithSuffix(Match match, string suffix) =>
        TryParseChineseInteger(match.Groups[1].Value, out var value)
            ? value.ToString(CultureInfo.InvariantCulture) + suffix
            : match.Value;

    private static bool TryParseChineseInteger(string value, out int result)
    {
        result = 0;
        if (string.IsNullOrEmpty(value))
        {
            return false;
        }

        if (value.All(ChineseDigits.ContainsKey))
        {
            var digits = new StringBuilder(value.Length);
            foreach (var character in value)
            {
                digits.Append(ChineseDigits[character].ToString(CultureInfo.InvariantCulture));
            }

            return int.TryParse(
                digits.ToString(),
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out result);
        }

        var total = 0;
        var section = 0;
        var number = 0;
        foreach (var character in value)
        {
            if (ChineseDigits.TryGetValue(character, out var digit))
            {
                number = digit;
                continue;
            }

            var unit = character switch
            {
                '十' => 10,
                '百' => 100,
                '千' => 1000,
                '万' => 10_000,
                _ => 0,
            };
            if (unit == 0)
            {
                return false;
            }

            if (unit == 10_000)
            {
                section += number;
                total = checked(total + (Math.Max(section, 1) * unit));
                section = 0;
                number = 0;
            }
            else
            {
                section = checked(section + (Math.Max(number, 1) * unit));
                number = 0;
            }
        }

        result = checked(total + section + number);
        return true;
    }

    private static string OptimizePunctuation(
        string text,
        int cjkThreshold,
        int wordThreshold)
    {
        var protectedText = ProtectedRegions.Mask(text);
        var result = protectedText.Masked;
        var cjkCount = CountCjk(result);
        if (cjkCount >= cjkThreshold)
        {
            result = ConvertCjkAdjacentPunctuation(result);
        }

        result = RepeatedPunctuationRegex().Replace(result, "$1$1");
        var trimmed = result.TrimEnd();
        if (trimmed.Length > 0 && !IsSentenceEnding(trimmed[^1]))
        {
            if (cjkCount >= 2)
            {
                result += "。";
            }
            else if (trimmed.Contains(' ')
                && char.IsLetter(trimmed[^1])
                && EnglishWordRegex().Count(trimmed) >= wordThreshold)
            {
                result += ".";
            }
        }

        return ProtectedRegions.Unmask(result, protectedText.Regions);
    }

    private static string ConvertCjkAdjacentPunctuation(string text)
    {
        var mapping = new Dictionary<char, char>
        {
            [','] = '，',
            ['.'] = '。',
            ['!'] = '！',
            ['?'] = '？',
            [';'] = '；',
            [':'] = '：',
            ['('] = '（',
            [')'] = '）',
        };
        var characters = text.ToCharArray();
        for (var index = 0; index < characters.Length; index++)
        {
            if (!mapping.TryGetValue(characters[index], out var fullWidth))
            {
                continue;
            }

            var previousIsCjk = index > 0 && IsCjk(characters[index - 1]);
            var nextIsCjk = index + 1 < characters.Length && IsCjk(characters[index + 1]);
            if (previousIsCjk || nextIsCjk)
            {
                characters[index] = fullWidth;
            }
        }

        return new string(characters);
    }

    private static string AddCjkLatinSpacing(string text)
    {
        var protectedText = ProtectedRegions.Mask(text);
        var result = CjkBeforeLatinOrDigitRegex().Replace(
            protectedText.Masked,
            "$1 $2");
        result = LatinOrDigitBeforeCjkRegex().Replace(result, "$1 $2");
        result = DigitBeforeDateUnitRegex().Replace(result, "$1$2");
        result = DateUnitBeforeDigitRegex().Replace(result, "$1$2");
        result = CjkBeforeCompactDateRegex().Replace(result, "$1$2");
        return ProtectedRegions.Unmask(result, protectedText.Regions);
    }

    private static string BreakLongSentences(
        string text,
        int wordThreshold,
        int cjkThreshold) => string.Join(
            '\n',
            text.Split('\n').Select(line =>
                BreakLongLine(line, wordThreshold, cjkThreshold)));

    private static string BreakLongLine(
        string line,
        int wordThreshold,
        int cjkThreshold)
    {
        var trimmed = line.Trim();
        if (trimmed.Length == 0
            || !ExceedsThreshold(trimmed, wordThreshold, cjkThreshold))
        {
            return line;
        }

        List<string> segments = [];
        var segment = new StringBuilder();
        foreach (var character in trimmed)
        {
            segment.Append(character);
            if (character is '，' or '；' or '、' or ',' or ';' or '。' or '！' or '？'
                or '.' or '!' or '?')
            {
                segments.Add(segment.ToString());
                segment.Clear();
            }
        }

        if (segment.Length > 0)
        {
            segments.Add(segment.ToString());
        }

        if (segments.Count <= 1)
        {
            return line;
        }

        List<string> lines = [];
        var current = new StringBuilder();
        foreach (var next in segments)
        {
            var candidate = current.ToString() + next;
            if (current.Length > 0
                && ExceedsThreshold(candidate, wordThreshold, cjkThreshold))
            {
                lines.Add(current.ToString().Trim());
                current.Clear();
            }

            current.Append(next);
            if (ExceedsThreshold(current.ToString(), wordThreshold, cjkThreshold))
            {
                lines.Add(current.ToString().Trim());
                current.Clear();
            }
        }

        if (current.Length > 0)
        {
            lines.Add(current.ToString().Trim());
        }

        return string.Join('\n', lines);
    }

    private static bool ExceedsThreshold(
        string text,
        int wordThreshold,
        int cjkThreshold) =>
        CountCjk(text) > cjkThreshold
        || EnglishWordRegex().Count(text) > wordThreshold;

    private static string CapitalizeNaturalLines(string text) => string.Join(
        '\n',
        text.Split('\n').Select(CapitalizeNaturalLine));

    private static string CapitalizeNaturalLine(string line)
    {
        var trimmed = line.TrimStart();
        if (trimmed.Length == 0
            || !char.IsAsciiLetterLower(trimmed[0])
            || !trimmed.Contains(' '))
        {
            return line;
        }

        var lower = trimmed.ToLowerInvariant();
        string[] codePrefixes =
        [
            "http://",
            "https://",
            "ftp://",
            "npm ",
            "git ",
            "cd ",
            "ls ",
            "sudo ",
            "pip ",
            "brew ",
        ];
        if (codePrefixes.Any(lower.StartsWith)
            || trimmed[0] is '/' or '`' or '#')
        {
            return line;
        }

        var firstWord = trimmed.Split(' ', 2)[0];
        if (firstWord.Contains('_') || firstWord.Skip(1).Any(char.IsUpper))
        {
            return line;
        }

        var leadingLength = line.Length - trimmed.Length;
        return line[..leadingLength]
            + char.ToUpperInvariant(trimmed[0])
            + trimmed[1..];
    }

    private static int CountCjk(string text) => text.Count(IsCjk);

    private static bool IsCjk(char value) => value is >= '\u3400' and <= '\u9FFF';

    private static bool IsSentenceEnding(char value) =>
        value is '。' or '.' or '！' or '!' or '？' or '?' or '…';

    private sealed record ProtectedRegion(string Placeholder, string Original);

    private sealed record ProtectedText(
        string Masked,
        IReadOnlyList<ProtectedRegion> Regions);

    private static class ProtectedRegions
    {
        public static ProtectedText Mask(string text)
        {
            var masked = text;
            List<ProtectedRegion> regions = [];
            Regex[] patterns =
            [
                BacktickRegex(),
                UrlRegex(),
                EmailRegex(),
                PathRegex(),
                VersionRegex(),
                DottedIdentifierRegex(),
            ];
            for (var patternIndex = 0; patternIndex < patterns.Length; patternIndex++)
            {
                var regex = patterns[patternIndex];
                masked = regex.Replace(masked, match =>
                {
                    var placeholder = $"zzVXF{patternIndex}R{regions.Count}zz";
                    regions.Add(new ProtectedRegion(placeholder, match.Value));
                    return placeholder;
                });
            }

            return new ProtectedText(masked, regions);
        }

        public static string Unmask(
            string text,
            IReadOnlyList<ProtectedRegion> regions)
        {
            var result = text;
            foreach (var region in regions)
            {
                result = result.Replace(
                    region.Placeholder,
                    region.Original,
                    StringComparison.Ordinal);
            }

            return result;
        }
    }

    [GeneratedRegex(
        @"[嗯呃唔额](?:[，。！？,.!?；;：:、]\s?)?",
        RegexOptions.CultureInvariant)]
    private static partial Regex CjkFillerRegex();

    [GeneratedRegex(
        @"\b(?:um|uh|hmm|er|uhm|umm|uhh|erm)\b[，。！？,.!?；;：:、]?\s?",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex LatinFillerRegex();

    [GeneratedRegex(@"\s{2,}", RegexOptions.CultureInvariant)]
    private static partial Regex RepeatedWhitespaceRegex();

    [GeneratedRegex(@"([零〇一二三四五六七八九]{2,4})年", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseYearRegex();

    [GeneratedRegex(@"百分之([零〇一二三四五六七八九十百千万两]+)", RegexOptions.CultureInvariant)]
    private static partial Regex ChinesePercentRegex();

    [GeneratedRegex(@"([零〇一二三四五六七八九十百千万两]+)月", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseMonthRegex();

    [GeneratedRegex(@"([零〇一二三四五六七八九十百千万两]+)日", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseDayRegex();

    [GeneratedRegex(@"([零〇一二三四五六七八九十百千万两]+)点", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseHourRegex();

    [GeneratedRegex(@"([零〇一二三四五六七八九十百千万两]+)分", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseMinuteRegex();

    [GeneratedRegex(
        @"([零〇一二三四五六七八九十百千万两]+)(个人|个|人|次|台|条|件|份|米|公里|小时|分钟|秒)",
        RegexOptions.CultureInvariant)]
    private static partial Regex ChineseQuantityRegex();

    [GeneratedRegex(
        @"([，。！？,.!?；;：:])\1{2,}",
        RegexOptions.CultureInvariant)]
    private static partial Regex RepeatedPunctuationRegex();

    [GeneratedRegex(@"[A-Za-z]+(?:'[A-Za-z]+)?", RegexOptions.CultureInvariant)]
    private static partial Regex EnglishWordRegex();

    [GeneratedRegex(
        @"([\u3400-\u9FFF])([A-Za-z0-9\u00C0-\u02AF\u0370-\u04FF])",
        RegexOptions.CultureInvariant)]
    private static partial Regex CjkBeforeLatinOrDigitRegex();

    [GeneratedRegex(
        @"([A-Za-z0-9\u00C0-\u02AF\u0370-\u04FF])([\u3400-\u9FFF])",
        RegexOptions.CultureInvariant)]
    private static partial Regex LatinOrDigitBeforeCjkRegex();

    [GeneratedRegex(@"([0-9])\s+([年月日号点分秒])", RegexOptions.CultureInvariant)]
    private static partial Regex DigitBeforeDateUnitRegex();

    [GeneratedRegex(@"([年月日号点分秒])\s+([0-9]+)", RegexOptions.CultureInvariant)]
    private static partial Regex DateUnitBeforeDigitRegex();

    [GeneratedRegex(
        @"([\u3400-\u9FFF])\s+([0-9]+[年月日号点分秒])",
        RegexOptions.CultureInvariant)]
    private static partial Regex CjkBeforeCompactDateRegex();

    [GeneratedRegex(@"`[^`]+`", RegexOptions.CultureInvariant)]
    private static partial Regex BacktickRegex();

    [GeneratedRegex(
        @"https?://[^\s\u3400-\u9FFF，。！？；：]+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex UrlRegex();

    [GeneratedRegex(
        @"[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z0-9]+",
        RegexOptions.CultureInvariant)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(
        @"(?:[A-Za-z]:\\(?:[A-Za-z0-9_. -]+\\?)+|(?:/[A-Za-z0-9_.-]+)+)",
        RegexOptions.CultureInvariant)]
    private static partial Regex PathRegex();

    [GeneratedRegex(@"\b\d+\.\d+(?:\.\d+)*\b", RegexOptions.CultureInvariant)]
    private static partial Regex VersionRegex();

    [GeneratedRegex(
        @"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b",
        RegexOptions.CultureInvariant)]
    private static partial Regex DottedIdentifierRegex();
}
