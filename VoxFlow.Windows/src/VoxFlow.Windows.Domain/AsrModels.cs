using System.Text.Json.Serialization;

namespace VoxFlow.Windows.Domain;

public enum AsrProviderId
{
    [JsonStringEnumMemberName("qwen3_asr")]
    Qwen,

    [JsonStringEnumMemberName("tencent_cloud_asr")]
    TencentCloud,

    [JsonStringEnumMemberName("aliyun_dashscope_asr")]
    AliyunDashScope,

    [JsonStringEnumMemberName("volcengine_doubao_asr")]
    Volcengine,
}

public enum QwenVariant
{
    [JsonStringEnumMemberName("0.6b")]
    Qwen06B,

    [JsonStringEnumMemberName("1.7b")]
    Qwen17B,
}

public enum RecognitionLanguage
{
    [JsonStringEnumMemberName("auto")]
    Automatic,

    [JsonStringEnumMemberName("zh-CN")]
    ChineseMandarin,

    [JsonStringEnumMemberName("en-US")]
    English,

    [JsonStringEnumMemberName("ja-JP")]
    Japanese,

    [JsonStringEnumMemberName("ko-KR")]
    Korean,
}

public static class QwenVariantExtensions
{
    public static string DisplayName(this QwenVariant variant) => variant switch
    {
        QwenVariant.Qwen06B => "Qwen 0.6B",
        QwenVariant.Qwen17B => "Qwen 1.7B",
        _ => throw new ArgumentOutOfRangeException(nameof(variant), variant, null),
    };
}

public sealed record AsrSelection
{
    [JsonConstructor]
    public AsrSelection(AsrProviderId provider, QwenVariant? qwenVariant)
    {
        if (provider == AsrProviderId.Qwen && qwenVariant is null)
        {
            throw new ArgumentException(
                "A Qwen ASR selection requires a model variant.",
                nameof(qwenVariant));
        }

        if (provider != AsrProviderId.Qwen && qwenVariant is not null)
        {
            throw new ArgumentException(
                "Cloud ASR selections cannot carry a Qwen model variant.",
                nameof(qwenVariant));
        }

        Provider = provider;
        QwenVariant = qwenVariant;
    }

    public AsrProviderId Provider { get; }

    public QwenVariant? QwenVariant { get; }
}
