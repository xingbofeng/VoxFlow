using System.Globalization;
using System.Text;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Infrastructure.Ocr;

/// <summary>
/// Runs fixed-language OCR across physical 0/90/180/270-degree PNG candidates.
/// Every returned line bound is normalized back to the original image's
/// top-left-origin, half-open physical-pixel coordinate space.
/// </summary>
public sealed class TesseractScreenshotOcrAdapter : IScreenshotOcrEngine
{
    private const double MinimumRotatedConfidenceGain = 2;
    private const double FullCoverageRelativeCharacterCount = 0.50;
    private const double MaximumSparseCoveragePenalty = 30;

    private readonly TesseractRuntimeLocator runtime;
    private readonly ITesseractRuntimeVerifier verifier;
    private readonly ITesseractOcrProcessRunner process;
    private readonly IScreenshotOcrImageCandidateProvider imageCandidates;
    private readonly TimeSpan timeout;

    public TesseractScreenshotOcrAdapter(
        TesseractRuntimeLocator runtime,
        ITesseractRuntimeVerifier verifier,
        ITesseractOcrProcessRunner process,
        TimeSpan? timeout = null)
        : this(
            runtime,
            verifier,
            process,
            new WindowsScreenshotOcrImageCandidateProvider(),
            timeout)
    {
    }

    internal TesseractScreenshotOcrAdapter(
        TesseractRuntimeLocator runtime,
        ITesseractRuntimeVerifier verifier,
        ITesseractOcrProcessRunner process,
        IScreenshotOcrImageCandidateProvider imageCandidates,
        TimeSpan? timeout = null)
    {
        this.runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        this.verifier = verifier ?? throw new ArgumentNullException(nameof(verifier));
        this.process = process ?? throw new ArgumentNullException(nameof(process));
        this.imageCandidates = imageCandidates ?? throw new ArgumentNullException(nameof(imageCandidates));
        this.timeout = timeout ?? TesseractOcrAdapter.DefaultTimeout;
        if (this.timeout <= TimeSpan.Zero || this.timeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }
    }

    public async Task<ScreenshotOcrEngineResult> RecognizeAsync(
        ScreenshotOcrEngineRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        var verified = verifier.Verify(runtime.RuntimeDirectory);
        if (!verified.IsValid || verified.ExecutablePath is null || verified.TessdataPath is null)
        {
            return new(ScreenshotOcrEngineStatus.RuntimeUnavailable);
        }
        if (!File.Exists(request.ImagePath))
        {
            return new(ScreenshotOcrEngineStatus.InputUnavailable);
        }

        using var deadline = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            deadline.Token);
        try
        {
            using var candidates = await imageCandidates.CreateAsync(request.ImagePath, linked.Token)
                .ConfigureAwait(false);
            List<OrientationAttempt> attempts = [];
            var sawSuccessfulProcess = false;
            foreach (var candidate in candidates.Candidates)
            {
                linked.Token.ThrowIfCancellationRequested();
                if (!ScreenshotOcrOrientationMapper.HasExpectedDimensions(
                        candidate,
                        candidates.OriginalPixelWidth,
                        candidates.OriginalPixelHeight))
                {
                    continue;
                }
                var result = await process.RunAsync(
                    new TesseractOcrProcessRequest(
                        verified.ExecutablePath,
                        candidate.ImagePath,
                        verified.TessdataPath,
                        TesseractLanguageSelector.SelectWithEnglish(request.CurrentLanguage),
                        TesseractOcrOutputFormat.Tsv),
                    linked.Token).ConfigureAwait(false);
                if (result.ExitCode != 0)
                {
                    continue;
                }
                sawSuccessfulProcess = true;

                var parsedLines = TesseractTsvLineParser.Parse(result.StandardOutput);
                List<ScreenshotOcrLine> originalLines = [];
                foreach (var line in parsedLines)
                {
                    if (ScreenshotOcrOrientationMapper.TryMapToOriginal(
                            line.Bounds,
                            candidate.Rotation,
                            candidates.OriginalPixelWidth,
                            candidates.OriginalPixelHeight,
                            out var originalBounds))
                    {
                        originalLines.Add(new ScreenshotOcrLine(
                            line.Text,
                            line.Confidence,
                            originalBounds));
                    }
                }
                if (originalLines.Count > 0)
                {
                    attempts.Add(new OrientationAttempt(candidate.Rotation, originalLines));
                }
            }

            if (attempts.Count == 0)
            {
                return new(
                    sawSuccessfulProcess
                        ? ScreenshotOcrEngineStatus.Empty
                        : ScreenshotOcrEngineStatus.Failed);
            }
            var selected = SelectOrientation(attempts);
            return new(
                ScreenshotOcrEngineStatus.Succeeded,
                string.Join('\n', selected.Lines.Select(line => line.Text)),
                selected.Lines);
        }
        catch (OperationCanceledException) when (
            deadline.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            return new(ScreenshotOcrEngineStatus.TimedOut);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return new(ScreenshotOcrEngineStatus.Failed);
        }
    }

    private static OrientationAttempt SelectOrientation(IReadOnlyList<OrientationAttempt> attempts)
    {
        var maximumCharacterCount = attempts.Max(attempt => attempt.CharacterCount);
        var best = attempts
            .OrderByDescending(attempt => attempt.QualityScore(maximumCharacterCount))
            .ThenByDescending(attempt => attempt.CharacterCount)
            .ThenBy(attempt => attempt.Rotation)
            .First();
        var upright = attempts.FirstOrDefault(
            attempt => attempt.Rotation == ScreenshotImageRotation.None);
        return upright is not null
            && best.Rotation != ScreenshotImageRotation.None
            && best.QualityScore(maximumCharacterCount)
                < upright.QualityScore(maximumCharacterCount) + MinimumRotatedConfidenceGain
                ? upright
                : best;
    }

    private sealed class OrientationAttempt
    {
        public OrientationAttempt(
            ScreenshotImageRotation rotation,
            IReadOnlyList<ScreenshotOcrLine> lines)
        {
            Rotation = rotation;
            Lines = Array.AsReadOnly(lines.ToArray());
            CharacterCount = Lines.Sum(line => line.Text.Count(character => !char.IsWhiteSpace(character)));
            WeightedConfidence = Lines.Sum(line =>
                    line.Confidence * line.Text.Count(character => !char.IsWhiteSpace(character)))
                / Math.Max(1, CharacterCount);
        }

        public ScreenshotImageRotation Rotation { get; }

        /// <summary>Bounds are always in the original screenshot's physical pixels.</summary>
        public IReadOnlyList<ScreenshotOcrLine> Lines { get; }

        public int CharacterCount { get; }

        public double WeightedConfidence { get; }

        public double QualityScore(int maximumCharacterCount)
        {
            // Coverage is normalized against the most text-bearing orientation.
            // This prevents one accidental high-confidence token from outranking
            // a candidate that consistently recognizes the broader screenshot.
            var relativeCharacterCount = (double)CharacterCount
                / Math.Max(1, maximumCharacterCount);
            var coverage = Math.Min(
                1,
                relativeCharacterCount / FullCoverageRelativeCharacterCount);
            return WeightedConfidence - ((1 - coverage) * MaximumSparseCoveragePenalty);
        }
    }
}

internal static class TesseractTsvLineParser
{
    public static IReadOnlyList<ScreenshotOcrLine> Parse(string tsv)
    {
        if (string.IsNullOrWhiteSpace(tsv))
        {
            return [];
        }

        Dictionary<LineKey, LineBuilder> builders = [];
        List<LineKey> order = [];
        using var reader = new StringReader(tsv);
        var header = reader.ReadLine();
        if (header is null || !header.StartsWith("level\tpage_num\t", StringComparison.Ordinal))
        {
            return [];
        }

        while (reader.ReadLine() is { } row)
        {
            var columns = row.Split('\t', 12, StringSplitOptions.None);
            if (columns.Length != 12
                || !TryInt(columns[0], out var level)
                || level != 5
                || !TryInt(columns[1], out var page)
                || !TryInt(columns[2], out var block)
                || !TryInt(columns[3], out var paragraph)
                || !TryInt(columns[4], out var line)
                || !TryInt(columns[6], out var left)
                || !TryInt(columns[7], out var top)
                || !TryInt(columns[8], out var width)
                || !TryInt(columns[9], out var height)
                || !double.TryParse(
                    columns[10],
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var confidence)
                || left < 0
                || top < 0
                || width <= 0
                || height <= 0
                || confidence < 0
                || confidence > 100
                || string.IsNullOrWhiteSpace(columns[11]))
            {
                continue;
            }

            var key = new LineKey(page, block, paragraph, line);
            if (!builders.TryGetValue(key, out var builder))
            {
                builder = new LineBuilder();
                builders.Add(key, builder);
                order.Add(key);
            }
            try
            {
                builder.Add(columns[11].Trim(), confidence, left, top, width, height);
            }
            catch (OverflowException)
            {
                // Ignore malformed coordinates without failing the whole local OCR result.
            }
        }

        return order
            .Select(key => builders[key].Build())
            .Where(line => line is not null)
            .Cast<ScreenshotOcrLine>()
            .ToArray();
    }

    private static bool TryInt(string value, out int result) =>
        int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out result);

    private readonly record struct LineKey(int Page, int Block, int Paragraph, int Line);

    private sealed class LineBuilder
    {
        private readonly StringBuilder text = new();
        private double confidenceTotal;
        private int wordCount;
        private int left = int.MaxValue;
        private int top = int.MaxValue;
        private int right = int.MinValue;
        private int bottom = int.MinValue;

        public void Add(
            string word,
            double confidence,
            int wordLeft,
            int wordTop,
            int width,
            int height)
        {
            var wordRight = checked(wordLeft + width);
            var wordBottom = checked(wordTop + height);
            if (text.Length > 0
                && !(IsCjk(text[^1]) && IsCjk(word[0])))
            {
                text.Append(' ');
            }
            text.Append(word);
            confidenceTotal += confidence;
            wordCount++;
            left = Math.Min(left, wordLeft);
            top = Math.Min(top, wordTop);
            right = Math.Max(right, wordRight);
            bottom = Math.Max(bottom, wordBottom);
        }

        public ScreenshotOcrLine? Build() =>
            wordCount == 0
                ? null
                : new ScreenshotOcrLine(
                    text.ToString(),
                    confidenceTotal / wordCount,
                    new ScreenshotPixelBounds(left, top, right - left, bottom - top));

        private static bool IsCjk(char value) =>
            value is >= '\u2e80' and <= '\u9fff'
            or >= '\u3040' and <= '\u30ff'
            or >= '\uac00' and <= '\ud7af';
    }
}
