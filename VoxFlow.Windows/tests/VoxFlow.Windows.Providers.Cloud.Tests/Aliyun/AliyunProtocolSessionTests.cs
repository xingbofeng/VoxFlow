using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Aliyun;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Aliyun;

public sealed class AliyunProtocolSessionTests
{
    private const string ApiKey = "s" + "k-ws-protocol-test-sentinel";
    private static readonly Guid TaskId = new("11111111-2222-3333-4444-555555555555");
    private static readonly DateTimeOffset Now = new(
        2026,
        7,
        11,
        0,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public async Task Session_waits_for_task_started_then_streams_binary_PCM_and_finishes_task()
    {
        var socket = new ScriptedCloudWebSocket();
        socket.EnqueueText(ServerEvent("task-started"));
        var session = CreateSession(socket);
        var first = new byte[] { 0, 1, 2, 3 };
        var second = new byte[] { 4, 5, 6, 7 };

        await session.StartAsync(CancellationToken.None);
        await session.PushAudioAsync(first, CancellationToken.None);
        await session.PushAudioAsync(second, CancellationToken.None);
        await session.FinishAsync(CancellationToken.None);

        Assert.Equal(
            $"Bearer {ApiKey}",
            socket.Request!.Headers["Authorization"]);
        Assert.DoesNotContain(ApiKey, socket.Request.ToString(), StringComparison.Ordinal);
        Assert.Equal([first, second], socket.SentBinary.Select(value => value.ToArray()));
        Assert.Equal(2, socket.SentText.Count);

        using var run = JsonDocument.Parse(socket.SentText[0]);
        Assert.Equal("run-task", run.RootElement.GetProperty("header").GetProperty("action").GetString());
        Assert.Equal(TaskId.ToString(), run.RootElement.GetProperty("header").GetProperty("task_id").GetString());
        var runPayload = run.RootElement.GetProperty("payload");
        Assert.Equal("fun-asr-realtime", runPayload.GetProperty("model").GetString());
        Assert.Equal("pcm", runPayload.GetProperty("parameters").GetProperty("format").GetString());
        Assert.Equal(16_000, runPayload.GetProperty("parameters").GetProperty("sample_rate").GetInt32());

        using var finish = JsonDocument.Parse(socket.SentText[1]);
        Assert.Equal("finish-task", finish.RootElement.GetProperty("header").GetProperty("action").GetString());
        Assert.Equal(TaskId.ToString(), finish.RootElement.GetProperty("header").GetProperty("task_id").GetString());
    }

    [Fact]
    public async Task Sentence_end_results_accumulate_while_current_sentence_revises_until_unique_final()
    {
        var socket = new ScriptedCloudWebSocket();
        socket.EnqueueText(ServerEvent("task-started"));
        var session = CreateSession(socket);
        var partials = new ConcurrentQueue<AsrPartialResult>();
        var final = new TaskCompletionSource<AsrFinalResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var finalCount = 0;
        session.PartialReceived += (_, value) => partials.Enqueue(value);
        session.FinalReceived += (_, value) =>
        {
            Interlocked.Increment(ref finalCount);
            final.TrySetResult(value);
        };

        await session.StartAsync(CancellationToken.None);
        socket.EnqueueText(ResultEvent(sentenceId: 1, text: "你好，", sentenceEnd: true));
        socket.EnqueueText(ResultEvent(sentenceId: 2, text: "码上", sentenceEnd: false));
        socket.EnqueueText(ResultEvent(sentenceId: 2, text: "码上写。", sentenceEnd: true));
        socket.EnqueueText(ServerEvent("task-finished"));

        var finalResult = await final.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal("你好，码上写。", finalResult.Text);
        Assert.Equal(1, Volatile.Read(ref finalCount));
        Assert.Equal(
            ["你好，", "你好，码上", "你好，码上写。"],
            partials.Select(value => value.Text));
        Assert.Equal([1L, 2L, 3L], partials.Select(value => value.Revision));

        socket.EnqueueText(ServerEvent("task-finished"));
        await Task.Yield();
        Assert.Equal(1, Volatile.Read(ref finalCount));
    }

    [Fact]
    public async Task Provider_rejection_closes_session_and_never_exposes_bearer_secret()
    {
        var socket = new ScriptedCloudWebSocket();
        socket.EnqueueText(
            ServerEvent(
                "task-failed",
                errorCode: "InvalidApiKey",
                errorMessage: "authentication rejected"));
        var session = CreateSession(socket);

        var exception = await Assert.ThrowsAsync<AliyunAsrProtocolException>(async () =>
            await session.StartAsync(CancellationToken.None));

        Assert.Equal("authenticationFailed", exception.SafeErrorCode);
        Assert.DoesNotContain(ApiKey, exception.ToString(), StringComparison.Ordinal);
        Assert.True(socket.IsClosed);
    }

    [Fact]
    public async Task Missing_task_started_times_out_with_controlled_time_and_closes_socket()
    {
        var time = new ControlledTimeProvider(Now);
        var socket = new ScriptedCloudWebSocket();
        var session = CreateSession(
            socket,
            timeProvider: time,
            timeout: TimeSpan.FromSeconds(5));

        var start = session.StartAsync(CancellationToken.None).AsTask();
        await socket.TextSent.Task.WaitAsync(TimeSpan.FromSeconds(2));
        time.Advance(TimeSpan.FromSeconds(5));

        await Assert.ThrowsAsync<TimeoutException>(async () => await start);
        Assert.True(socket.IsClosed);
    }

    [Fact]
    public async Task Cancel_closes_transport_and_drops_late_result_callbacks()
    {
        var socket = new ScriptedCloudWebSocket();
        socket.EnqueueText(ServerEvent("task-started"));
        var session = CreateSession(socket);
        var partialCount = 0;
        var finalCount = 0;
        session.PartialReceived += (_, _) => Interlocked.Increment(ref partialCount);
        session.FinalReceived += (_, _) => Interlocked.Increment(ref finalCount);

        await session.StartAsync(CancellationToken.None);
        await session.CancelAsync(CancellationToken.None);
        socket.EnqueueText(ResultEvent(1, "late", sentenceEnd: true));
        socket.EnqueueText(ServerEvent("task-finished"));
        await Task.Yield();
        await Task.Yield();

        Assert.True(socket.IsClosed);
        Assert.Equal(0, Volatile.Read(ref partialCount));
        Assert.Equal(0, Volatile.Read(ref finalCount));
    }

    [Fact]
    public async Task Early_task_finished_stops_all_later_audio_sends()
    {
        var socket = new ScriptedCloudWebSocket();
        socket.EnqueueText(ServerEvent("task-started"));
        var session = CreateSession(socket);
        var final = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        session.FinalReceived += (_, _) => final.TrySetResult();

        await session.StartAsync(CancellationToken.None);
        await session.PushAudioAsync(new byte[] { 0, 1 }, CancellationToken.None);
        socket.EnqueueText(ResultEvent(1, "完成。", sentenceEnd: true));
        socket.EnqueueText(ServerEvent("task-finished"));
        await final.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await session.PushAudioAsync(new byte[] { 2, 3 }, CancellationToken.None);

        Assert.Single(socket.SentBinary);
    }

    private static AliyunRealtimeAsrSession CreateSession(
        ScriptedCloudWebSocket socket,
        TimeProvider? timeProvider = null,
        TimeSpan? timeout = null) => new(
        ApiKey,
        new SingleCloudWebSocketFactory(socket),
        taskIdGenerator: () => TaskId,
        timeProvider: timeProvider,
        connectionTimeout: timeout ?? TimeSpan.FromSeconds(30));

    private static string ServerEvent(
        string eventName,
        string? errorCode = null,
        string? errorMessage = null) => JsonSerializer.Serialize(new
        {
            header = new
            {
                task_id = TaskId.ToString(),
                @event = eventName,
                error_code = errorCode,
                error_message = errorMessage,
            },
            payload = new { },
        });

    private static string ResultEvent(int sentenceId, string text, bool sentenceEnd) =>
        JsonSerializer.Serialize(new
        {
            header = new
            {
                task_id = TaskId.ToString(),
                @event = "result-generated",
            },
            payload = new
            {
                output = new
                {
                    sentence = new
                    {
                        sentence_id = sentenceId,
                        text,
                        sentence_end = sentenceEnd,
                        heartbeat = false,
                    },
                },
            },
        });

    private sealed class SingleCloudWebSocketFactory(
        ICloudWebSocket socket) : ICloudWebSocketFactory
    {
        public ICloudWebSocket Create() => socket;
    }

    private sealed class ScriptedCloudWebSocket : ICloudWebSocket
    {
        private readonly Channel<CloudWebSocketReceiveMessage> incoming =
            Channel.CreateUnbounded<CloudWebSocketReceiveMessage>();
        private readonly object syncRoot = new();

        public CloudWebSocketConnectRequest? Request { get; private set; }

        public List<string> SentText { get; } = [];

        public List<ReadOnlyMemory<byte>> SentBinary { get; } = [];

        public bool IsClosed { get; private set; }

        public TaskCompletionSource TextSent { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask ConnectAsync(
            CloudWebSocketConnectRequest request,
            CancellationToken cancellationToken)
        {
            Request = request;
            return ValueTask.CompletedTask;
        }

        public ValueTask SendBinaryAsync(
            ReadOnlyMemory<byte> payload,
            CancellationToken cancellationToken)
        {
            lock (syncRoot)
            {
                if (!IsClosed)
                {
                    SentBinary.Add(payload.ToArray());
                }
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask SendTextAsync(
            string payload,
            CancellationToken cancellationToken)
        {
            lock (syncRoot)
            {
                SentText.Add(payload);
            }

            TextSent.TrySetResult();
            return ValueTask.CompletedTask;
        }

        public ValueTask<CloudWebSocketReceiveMessage> ReceiveAsync(
            CancellationToken cancellationToken) =>
            incoming.Reader.ReadAsync(cancellationToken);

        public ValueTask CloseAsync(CancellationToken cancellationToken)
        {
            IsClosed = true;
            incoming.Writer.TryWrite(CloudWebSocketReceiveMessage.Closed());
            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync()
        {
            incoming.Writer.TryComplete();
            return ValueTask.CompletedTask;
        }

        public void EnqueueText(string text) =>
            incoming.Writer.TryWrite(CloudWebSocketReceiveMessage.Text(text));
    }
}
