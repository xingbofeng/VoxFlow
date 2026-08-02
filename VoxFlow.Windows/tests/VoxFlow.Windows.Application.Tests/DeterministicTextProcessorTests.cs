using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Application.Tests;

public sealed class DeterministicTextProcessorTests
{
    [Fact]
    public void Defaults_match_the_original_first_release_Text_controls()
    {
        var settings = DeterministicTextProcessingSettings.Default;

        Assert.True(settings.Enabled);
        Assert.True(settings.SmartNumberRecognition);
        Assert.True(settings.PunctuationOptimization);
        Assert.False(settings.LongSentenceBreaking);
        Assert.True(settings.FillerWordFiltering);
        Assert.True(settings.CjkLatinSpacing);
        Assert.True(settings.AutoCapitalization);
        Assert.Equal(8, settings.LongSentenceWordThreshold);
        Assert.Equal(12, settings.LongSentenceCjkThreshold);
        Assert.Equal(3, settings.PunctuationCjkThreshold);
        Assert.Equal(4, settings.PunctuationWordThreshold);
    }

    [Fact]
    public void Master_switch_off_makes_every_enabled_subprocessor_a_no_op()
    {
        var settings = DeterministicTextProcessingSettings.Default with
        {
            Enabled = false,
            LongSentenceBreaking = true,
            LongSentenceWordThreshold = 2,
            LongSentenceCjkThreshold = 2,
        };
        const string input = "嗯 hello世界,这是三个人的长句子，需要分行";

        Assert.Equal(input, DeterministicTextProcessor.Process(input, settings));
    }

    [Fact]
    public void Filler_filter_removes_only_curated_fillers_and_preserves_discourse_markers()
    {
        var settings = Only(feature => feature with { FillerWordFiltering = true });

        Assert.Equal(
            "其实这个方案 umami 很好，然后继续",
            DeterministicTextProcessor.Process(
                "嗯， 其实这个方案 um uh umami 很好，然后继续",
                settings));
        Assert.Equal(
            "啊哦哎这个",
            DeterministicTextProcessor.Process("啊哦哎这个", settings));
    }

    [Fact]
    public void Smart_numbers_convert_date_time_percent_and_quantities_but_not_idioms()
    {
        var settings = Only(feature => feature with { SmartNumberRecognition = true });

        Assert.Equal(
            "2026年7月11日3点15分，完成20%，共3个人，一心一意",
            DeterministicTextProcessor.Process(
                "二零二六年七月十一日三点十五分，完成百分之二十，共三个人，一心一意",
                settings));
    }

    [Fact]
    public void Punctuation_uses_editable_CJK_and_word_thresholds()
    {
        var baseSettings = Only(feature => feature with
        {
            PunctuationOptimization = true,
            PunctuationCjkThreshold = 3,
            PunctuationWordThreshold = 4,
        });

        Assert.Equal(
            "今天调试，明天验证。",
            DeterministicTextProcessor.Process("今天调试,明天验证", baseSettings));
        Assert.Equal(
            "one two three",
            DeterministicTextProcessor.Process("one two three", baseSettings));
        Assert.Equal(
            "one two three four.",
            DeterministicTextProcessor.Process("one two three four", baseSettings));
        Assert.Equal(
            "今天,OK。",
            DeterministicTextProcessor.Process(
                "今天,OK",
                baseSettings with { PunctuationCjkThreshold = 10 }));
    }

    [Fact]
    public void CJK_Latin_spacing_preserves_URL_email_version_backtick_and_compact_dates()
    {
        var settings = Only(feature => feature with { CjkLatinSpacing = true });

        Assert.Equal(
            "使用 VoxFlow 2.1 输入，访问 https://example.com/v1，联系 a@example.com，运行 `git status`，日期2026年7月11日",
            DeterministicTextProcessor.Process(
                "使用VoxFlow 2.1输入，访问https://example.com/v1，联系a@example.com，运行`git status`，日期2026年7月11日",
                settings));
    }

    [Fact]
    public void Long_sentence_breaking_splits_only_at_semantic_boundaries_after_threshold()
    {
        var settings = Only(feature => feature with
        {
            LongSentenceBreaking = true,
            LongSentenceWordThreshold = 5,
            LongSentenceCjkThreshold = 8,
        });

        Assert.Equal(
            "我们先确认录音状态，\n再检查转写结果，\n最后同步团队。",
            DeterministicTextProcessor.Process(
                "我们先确认录音状态，再检查转写结果，最后同步团队。",
                settings));
        Assert.Equal(
            "short sentence",
            DeterministicTextProcessor.Process("short sentence", settings));
    }

    [Fact]
    public void Auto_capitalization_handles_natural_lines_but_preserves_code_context()
    {
        var settings = Only(feature => feature with { AutoCapitalization = true });

        Assert.Equal(
            "Hello world\nSecond natural line",
            DeterministicTextProcessor.Process(
                "hello world\nsecond natural line",
                settings,
                isCodingContext: false));
        Assert.Equal(
            "hello world",
            DeterministicTextProcessor.Process(
                "hello world",
                settings,
                isCodingContext: true));
        Assert.Equal(
            "git status",
            DeterministicTextProcessor.Process("git status", settings));
    }

    [Theory]
    [InlineData(0, 12, 3, 4)]
    [InlineData(8, 0, 3, 4)]
    [InlineData(8, 12, 0, 4)]
    [InlineData(8, 12, 3, 0)]
    [InlineData(1001, 12, 3, 4)]
    public void Threshold_editor_rejects_values_outside_supported_range(
        int longWords,
        int longCjk,
        int punctuationCjk,
        int punctuationWords)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new DeterministicTextProcessingSettings(
                Enabled: true,
                SmartNumberRecognition: true,
                PunctuationOptimization: true,
                LongSentenceBreaking: false,
                FillerWordFiltering: true,
                CjkLatinSpacing: true,
                AutoCapitalization: true,
                LongSentenceWordThreshold: longWords,
                LongSentenceCjkThreshold: longCjk,
                PunctuationCjkThreshold: punctuationCjk,
                PunctuationWordThreshold: punctuationWords));
    }

    private static DeterministicTextProcessingSettings Only(
        Func<DeterministicTextProcessingSettings, DeterministicTextProcessingSettings> enable) =>
        enable(new DeterministicTextProcessingSettings(
            Enabled: true,
            SmartNumberRecognition: false,
            PunctuationOptimization: false,
            LongSentenceBreaking: false,
            FillerWordFiltering: false,
            CjkLatinSpacing: false,
            AutoCapitalization: false,
            LongSentenceWordThreshold: 8,
            LongSentenceCjkThreshold: 12,
            PunctuationCjkThreshold: 3,
            PunctuationWordThreshold: 4));
}
