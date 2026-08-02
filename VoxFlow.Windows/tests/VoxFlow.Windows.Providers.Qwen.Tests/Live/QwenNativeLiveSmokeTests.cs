using System.Buffers.Binary;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen.Native;
using VoxFlow.Windows.Providers.Qwen.Runtime;

namespace VoxFlow.Windows.Providers.Qwen.Tests.Live;

public sealed class QwenNativeLiveSmokeTests
{
    [Fact]
    [Trait("Category", "Live")]
    public async Task Managed_C_ABI_stream_transcribes_the_fixed_WAV_with_the_official_06B_model()
    {
        if (!string.Equals(
            Environment.GetEnvironmentVariable("VOXFLOW_LIVE_QWEN_ENABLED"),
            "1",
            StringComparison.Ordinal))
        {
            return;
        }

        string nativeDll = Required("VOXFLOW_LIVE_QWEN_NATIVE_DLL");
        string modelDirectory = Required("VOXFLOW_LIVE_QWEN_MODEL_DIR");
        QwenNativeLibrary.ConfigureResolver(nativeDll);
        var api = new QwenNativeApi();
        await using var cache = new QwenRuntimeCache(api);
        QwenRuntimeLease lease = await cache.AcquireAsync(
            "qwen3-asr-0.6b",
            modelDirectory,
            CancellationToken.None);
        await using var session = new QwenNativeDictationSession(api, lease, variant: 0);
        var final = new TaskCompletionSource<AsrFinalResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var failure = new TaskCompletionSource<VoxFlowError>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        int partials = 0;
        int finals = 0;
        session.PartialReceived += (_, _) => Interlocked.Increment(ref partials);
        session.FinalReceived += (_, value) =>
        {
            Interlocked.Increment(ref finals);
            final.TrySetResult(value);
        };
        session.Failed += (_, value) => failure.TrySetResult(value);

        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(8));
        await session.StartAsync(timeout.Token);
        foreach (ReadOnlyMemory<byte> frame in ReadFixturePcmChunks())
        {
            await session.PushAudioAsync(frame, timeout.Token);
        }
        await session.FinishAsync(timeout.Token);

        Task completed = await Task.WhenAny(final.Task, failure.Task)
            .WaitAsync(timeout.Token);
        if (completed == failure.Task)
        {
            VoxFlowError error = await failure.Task;
            throw new QwenLiveSmokeException(error);
        }

        AsrFinalResult result = await final.Task;
        Assert.False(string.IsNullOrWhiteSpace(result.Text));
        Assert.True(partials > 0);
        Assert.Equal(1, finals);
    }

    private static IReadOnlyList<ReadOnlyMemory<byte>> ReadFixturePcmChunks()
    {
        string path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "zh_short.wav");
        byte[] wave = File.ReadAllBytes(path);
        if (wave.Length < 44 ||
            !wave.AsSpan(0, 4).SequenceEqual("RIFF"u8) ||
            !wave.AsSpan(8, 4).SequenceEqual("WAVE"u8))
        {
            throw new InvalidDataException("The Qwen live fixture is not a RIFF/WAVE file.");
        }

        int cursor = 12;
        ReadOnlyMemory<byte> pcm = default;
        bool formatVerified = false;
        while (cursor + 8 <= wave.Length)
        {
            ReadOnlySpan<byte> chunkId = wave.AsSpan(cursor, 4);
            int size = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(
                wave.AsSpan(cursor + 4, 4)));
            int content = cursor + 8;
            if (content + size > wave.Length)
            {
                throw new InvalidDataException("The Qwen live fixture has an invalid chunk.");
            }

            if (chunkId.SequenceEqual("fmt "u8))
            {
                formatVerified = size >= 16 &&
                    BinaryPrimitives.ReadUInt16LittleEndian(wave.AsSpan(content, 2)) == 1 &&
                    BinaryPrimitives.ReadUInt16LittleEndian(wave.AsSpan(content + 2, 2)) == 1 &&
                    BinaryPrimitives.ReadUInt32LittleEndian(wave.AsSpan(content + 4, 4)) == 16_000 &&
                    BinaryPrimitives.ReadUInt16LittleEndian(wave.AsSpan(content + 14, 2)) == 16;
            }
            else if (chunkId.SequenceEqual("data"u8))
            {
                pcm = wave.AsMemory(content, size);
            }

            cursor = content + size + (size & 1);
        }

        if (!formatVerified || pcm.IsEmpty)
        {
            throw new InvalidDataException("The Qwen live fixture must be PCM S16LE mono at 16 kHz.");
        }

        const int chunkBytes = 16_000 * sizeof(short) / 10;
        List<ReadOnlyMemory<byte>> frames = [];
        for (int offset = 0; offset < pcm.Length; offset += chunkBytes)
        {
            frames.Add(pcm.Slice(offset, Math.Min(chunkBytes, pcm.Length - offset)));
        }
        return frames;
    }

    private static string Required(string name)
    {
        string? value = Environment.GetEnvironmentVariable(name)?.Trim();
        return string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException(
                $"Required private Qwen live-test variable is missing: {name}.")
            : value;
    }

    private sealed class QwenLiveSmokeException(VoxFlowError error)
        : Exception($"Qwen native live smoke failed ({error.Provider}/{error.Code}).");
}
