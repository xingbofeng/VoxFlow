using System.Buffers.Binary;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.OpenAI;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Providers.Cloud.Volcengine;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Live;

/// <summary>
/// Explicit, billable local smokes. CI never sets VOXFLOW_LIVE_ENABLED=1.
/// Tests use a repository-owned, non-personal 16 kHz mono PCM fixture and do
/// not print credentials, request URLs, provider messages, or transcripts.
/// </summary>
public sealed class CloudAsrLiveSmokeTests
{
    [Fact]
    [Trait("Category", "Live")]
    public async Task OpenAI_compatible_stream_returns_a_nonempty_final()
    {
        if (!LiveEnabled())
        {
            return;
        }

        var configuration = new OpenAiClientConfiguration(
            new Uri(Required("VOXFLOW_LIVE_OPENAI_COMPAT_BASE_URL")),
            Required("VOXFLOW_LIVE_OPENAI_COMPAT_MODEL"),
            Required("VOXFLOW_LIVE_OPENAI_API_KEY"));
        using var http = new HttpClient
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiChatCompletionsClient(http);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        string? final = null;

        await foreach (var snapshot in client.StreamRefinementAsync(
            configuration,
            Required("VOXFLOW_LIVE_OPENAI_COMPAT_PROMPT"),
            timeout.Token))
        {
            final = snapshot;
        }

        Assert.False(string.IsNullOrWhiteSpace(final));
    }

    [Fact]
    [Trait("Category", "Live")]
    public async Task Tencent_streaming_ASR_returns_a_nonempty_final()
    {
        if (!LiveEnabled())
        {
            return;
        }

        var credentials = new TencentAsrCredentials(
            Required("VOXFLOW_LIVE_TENCENT_ASR_APP_ID"),
            Required("VOXFLOW_LIVE_TENCENT_ASR_SECRET_ID"),
            Required("VOXFLOW_LIVE_TENCENT_ASR_SECRET_KEY"));
        var options = TencentAsrOptions.Default with
        {
            EngineModelType = Environment.GetEnvironmentVariable(
                "VOXFLOW_LIVE_TENCENT_ASR_ENGINE_MODEL_TYPE")?.Trim()
                is { Length: > 0 } engine
                ? engine
                : TencentAsrDefaults.EngineModelType,
        };
        await using var session = new TencentAsrSession(
            credentials,
            options,
            Guid.NewGuid().ToString("N"),
            new TencentSignedUrlBuilder(),
            new ClientWebSocketAdapter(),
            finalTimeout: TimeSpan.FromSeconds(30));

        await RunSessionAsync(session);
    }

    [Fact]
    [Trait("Category", "Live")]
    public async Task Aliyun_streaming_ASR_returns_a_nonempty_final()
    {
        if (!LiveEnabled())
        {
            return;
        }

        await using var session = new AliyunRealtimeAsrSession(
            Required("VOXFLOW_LIVE_ALIYUN_ASR_API_KEY"),
            new ClientWebSocketFactory(),
            connectionTimeout: TimeSpan.FromSeconds(15));

        await RunSessionAsync(session);
    }

    [Fact]
    [Trait("Category", "Live")]
    public async Task Volcengine_streaming_ASR_returns_a_nonempty_final()
    {
        if (!LiveEnabled())
        {
            return;
        }

        var credentials = new VolcengineAsrCredentials(
            Required("VOXFLOW_LIVE_VOLCENGINE_ASR_APP_ID"),
            Required("VOXFLOW_LIVE_VOLCENGINE_ASR_ACCESS_TOKEN"),
            Required("VOXFLOW_LIVE_VOLCENGINE_ASR_SECRET_KEY"));
        await using var session = new VolcengineRealtimeAsrSession(
            credentials,
            new ClientWebSocketFactory(),
            finalTimeout: TimeSpan.FromSeconds(30));

        await RunSessionAsync(session);
    }

    private static async Task RunSessionAsync(IDictationAsrSession session)
    {
        var final = new TaskCompletionSource<AsrFinalResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var failure = new TaskCompletionSource<VoxFlowError>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, value) => final.TrySetResult(value);
        session.Failed += (_, value) => failure.TrySetResult(value);

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(50));
        await session.StartAsync(timeout.Token);
        foreach (var chunk in ReadFixtureChunks())
        {
            if (final.Task.IsCompleted || failure.Task.IsCompleted)
            {
                break;
            }

            await session.PushAudioAsync(chunk, timeout.Token);
            await Task.Delay(TimeSpan.FromMilliseconds(100), timeout.Token);
        }

        if (!final.Task.IsCompleted && !failure.Task.IsCompleted)
        {
            await session.FinishAsync(timeout.Token);
        }

        var completed = await Task.WhenAny(
                final.Task,
                failure.Task,
                Task.Delay(TimeSpan.FromSeconds(35), timeout.Token))
            .ConfigureAwait(false);
        if (completed == failure.Task)
        {
            var error = await failure.Task.ConfigureAwait(false);
            throw new CloudLiveSmokeException(error);
        }

        Assert.Same(final.Task, completed);
        var result = await final.Task.ConfigureAwait(false);
        Assert.False(string.IsNullOrWhiteSpace(result.Text));
    }

    private static IReadOnlyList<ReadOnlyMemory<byte>> ReadFixtureChunks()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "zh_short.wav");
        var wave = File.ReadAllBytes(path);
        if (wave.Length < 44
            || !wave.AsSpan(0, 4).SequenceEqual("RIFF"u8)
            || !wave.AsSpan(8, 4).SequenceEqual("WAVE"u8))
        {
            throw new InvalidDataException("The live ASR fixture is not a RIFF/WAVE file.");
        }

        var cursor = 12;
        ReadOnlyMemory<byte> pcm = default;
        var formatVerified = false;
        while (cursor + 8 <= wave.Length)
        {
            var chunkId = wave.AsSpan(cursor, 4);
            var size = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(
                wave.AsSpan(cursor + 4, 4)));
            var content = cursor + 8;
            if (size < 0 || content + size > wave.Length)
            {
                throw new InvalidDataException("The live ASR fixture has an invalid chunk.");
            }

            if (chunkId.SequenceEqual("fmt "u8))
            {
                if (size < 16
                    || BinaryPrimitives.ReadUInt16LittleEndian(wave.AsSpan(content, 2)) != 1
                    || BinaryPrimitives.ReadUInt16LittleEndian(wave.AsSpan(content + 2, 2)) != 1
                    || BinaryPrimitives.ReadUInt32LittleEndian(wave.AsSpan(content + 4, 4)) != 16_000
                    || BinaryPrimitives.ReadUInt16LittleEndian(wave.AsSpan(content + 14, 2)) != 16)
                {
                    throw new InvalidDataException(
                        "The live ASR fixture must be PCM S16LE mono at 16 kHz.");
                }

                formatVerified = true;
            }
            else if (chunkId.SequenceEqual("data"u8))
            {
                pcm = wave.AsMemory(content, size);
            }

            cursor = content + size + (size & 1);
        }

        if (!formatVerified || pcm.IsEmpty)
        {
            throw new InvalidDataException("The live ASR fixture has no usable PCM data.");
        }

        const int bytesPerHundredMilliseconds = 16_000 * sizeof(short) / 10;
        List<ReadOnlyMemory<byte>> chunks = [];
        for (var offset = 0; offset < pcm.Length; offset += bytesPerHundredMilliseconds)
        {
            chunks.Add(pcm.Slice(
                offset,
                Math.Min(bytesPerHundredMilliseconds, pcm.Length - offset)));
        }

        return chunks;
    }

    private static bool LiveEnabled() => string.Equals(
        Environment.GetEnvironmentVariable("VOXFLOW_LIVE_ENABLED"),
        "1",
        StringComparison.Ordinal);

    private static string Required(string name)
    {
        var value = Environment.GetEnvironmentVariable(name)?.Trim();
        return !string.IsNullOrEmpty(value)
            ? value
            : throw new InvalidOperationException(
                $"Required private live-test variable is missing: {name}.");
    }

    private sealed class CloudLiveSmokeException(VoxFlowError error)
        : Exception($"Cloud ASR live smoke failed ({error.Provider}/{error.Code}).");
}
