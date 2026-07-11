using System.Text.Json;

namespace VoxFlow.Windows.Providers.Cloud.Tencent;

internal sealed record TencentProtocolUpdate(
    string? PartialText,
    long PartialRevision,
    bool IsFinal,
    int ProviderCode);

internal sealed class TencentResultAccumulator
{
    private readonly SortedDictionary<int, Segment> segments = [];
    private string lastPartial = string.Empty;
    private long revision;

    public string CurrentText => string.Concat(segments.Values.Select(segment => segment.Text));

    public TencentProtocolUpdate Apply(string message)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(message);
        using var document = JsonDocument.Parse(message, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 32,
        });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("code", out var codeElement)
            || !codeElement.TryGetInt32(out var code))
        {
            throw new JsonException("Tencent ASR response did not contain a numeric code.");
        }

        string? partial = null;
        if (code == 0 && root.TryGetProperty("result", out var result))
        {
            ApplyResult(result);
            var current = CurrentText;
            if (!string.IsNullOrWhiteSpace(current)
                && !string.Equals(current, lastPartial, StringComparison.Ordinal))
            {
                lastPartial = current;
                partial = current;
                revision = checked(revision + 1);
            }
        }

        var isFinal = root.TryGetProperty("final", out var finalElement)
            && finalElement.TryGetInt32(out var final)
            && final == 1;
        return new TencentProtocolUpdate(partial, revision, isFinal, code);
    }

    private void ApplyResult(JsonElement result)
    {
        if (result.ValueKind != JsonValueKind.Object
            || !result.TryGetProperty("slice_type", out var sliceElement)
            || !sliceElement.TryGetInt32(out var sliceType)
            || !result.TryGetProperty("index", out var indexElement)
            || !indexElement.TryGetInt32(out var index)
            || index < 0)
        {
            throw new JsonException("Tencent ASR result metadata was invalid.");
        }

        if (sliceType is < 0 or > 2)
        {
            throw new JsonException("Tencent ASR slice type was invalid.");
        }

        var text = result.TryGetProperty("voice_text_str", out var textElement)
            && textElement.ValueKind == JsonValueKind.String
            ? textElement.GetString() ?? string.Empty
            : string.Empty;
        var stable = sliceType == 2;

        if (segments.TryGetValue(index, out var existing) && existing.IsStable)
        {
            return;
        }

        segments[index] = new Segment(text, stable);
    }

    private sealed record Segment(string Text, bool IsStable);
}
