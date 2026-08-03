using System.Text;
using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Tests;

/// <summary>
/// Full headless Agent Compose journey. The audio and ASR boundaries are
/// deterministic fakes, but the hotkey gesture, dictation lifecycle, context
/// envelope, JSONL runner, managed tool host, final-output policy and generic
/// no-injection boundary are the production implementations.
/// </summary>
public sealed class AgentComposeMockAudioEndToEndTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 13, 2, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Hotkey_mock_audio_ASR_Agent_tool_and_summary_complete_without_microphone_or_submit()
    {
        var workspace = Path.Combine(
            Path.GetTempPath(),
            "voxflow-agent-mock-audio-e2e-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workspace);
        var order = new List<string>();
        var session = new MockAsrSession("把回复写入输入框但不要发送", order);
        var audio = new MockAudioCapture(order);
        var target = Target();
        var selection = EditableSelection(target);
        var contextCapture = new AgentComposeContextCapture(
            new FixedTargetProvider(target),
            new AgentContextPipeline(new FixedContextReader(selection)));
        var textField = new CapturingTextField();
        var sidecar = new CapturingSidecarFactory(
            """
            {"schemaVersion":1,"event":"toolRequested","toolCall":{"id":"field-1","name":"text_field","arguments":{"action":"insert","text":"周三下午可以。"}}}
            {"schemaVersion":1,"event":"toolResolved","toolName":"text_field","result":{"ok":true,"toolName":"text_field","result":{"action":"insert"}}}
            {"schemaVersion":1,"event":"turnCompleted","summary":"已写入输入框，未发送。"}
            """);
        var execution = new AgentComposeExecutionService(
            new FixedLlmResolver(),
            new AgentComposePromptBuilder(),
            new BuiltinAgentSidecarRunner(sidecar),
            textField: new FixedTextFieldFactory(textField));
        var clipboard = new CapturingAgentClipboard();
        var summary = new CapturingSummary();
        var processor = new AgentComposeDictationPostProcessor(
            contextCapture,
            execution,
            _ => workspace,
            output: new AgentComposeOutputCoordinator(clipboard, summary));
        var genericOutput = new DiscardingOutput();
        await using var orchestrator = new DictationOrchestrator(
            new MockAsrProvider(session),
            audio,
            processor,
            genericOutput,
            new DiscardingHistory(),
            new CapturingProgress(),
            TimeProvider.System,
            TimeSpan.FromSeconds(2),
            contextCapture);
        AgentComposeReadinessResult? readinessFailure = null;
        var hotkey = new AgentComposeHotkeyController(
            new AgentChordGestureRecognizer(TimeSpan.FromMilliseconds(500)),
            () => orchestrator.Snapshot.Phase,
            StartAsync,
            orchestrator.StopAsync,
            orchestrator.CancelAsync,
            _ =>
            {
                order.Add("readiness");
                return ValueTask.FromResult(new AgentComposeReadinessInput(
                    SidecarAvailable: true,
                    AsrAvailability: AsrProviderAvailability.Ready,
                    HasDefaultProvider: true,
                    AgentCapabilityStatus: LlmAgentCapabilityStatus.Supported));
            },
            result => readinessFailure = result);

        try
        {
            await hotkey.HandleAsync(Agent(KeyTransition.Down, Now));
            await hotkey.HandleAsync(Agent(KeyTransition.Up, Now.AddMilliseconds(120)));
            Assert.Equal(DictationPhase.Recording, orchestrator.Snapshot.Phase);

            await hotkey.HandleAsync(Agent(KeyTransition.Down, Now.AddMilliseconds(300)));
            await hotkey.HandleAsync(Agent(KeyTransition.Up, Now.AddMilliseconds(420)));

            Assert.Equal(DictationPhase.Completed, orchestrator.Snapshot.Phase);
            Assert.Null(readinessFailure);
            Assert.True(order.IndexOf("readiness") < order.IndexOf("audio.start"));
            Assert.Equal(1, audio.StartCalls);
            Assert.Equal(1, audio.StopCalls);
            Assert.Equal(1, session.PushedFrames);
            Assert.Equal("把回复写入输入框但不要发送", sidecar.Request?.Instruction);
            Assert.Contains("<untrusted_context>", sidecar.Request!.Content.Single().Text, StringComparison.Ordinal);
            Assert.Contains("Selected text:", sidecar.Request.Content.Single().Text, StringComparison.Ordinal);
            Assert.Equal(["周三下午可以。"], textField.Inserted);
            Assert.Contains("\"toolName\":\"text_field\"", sidecar.ToolResultsWritten, StringComparison.Ordinal);
            Assert.Null(clipboard.Text);
            Assert.Equal("已写入输入框，未发送。", summary.Text);
            Assert.Equal(1, genericOutput.Writes);
            Assert.Equal("已写入输入框，未发送。", genericOutput.LastText);
        }
        finally
        {
            Directory.Delete(workspace, recursive: true);
        }

        async ValueTask StartAsync(CancellationToken cancellationToken)
        {
            var outcome = await orchestrator.StartAsync(cancellationToken);
            Assert.Equal(DictationStartOutcome.Started, outcome);
        }
    }

    private static InteractiveHotkeyRouteEvent Agent(
        KeyTransition transition,
        DateTimeOffset timestamp) => new(
        InteractiveHotkeyAction.AgentCompose,
        transition,
        timestamp);

    private static ForegroundTargetSnapshot Target() => new(
        101,
        202,
        "notepad.exe",
        "Reply <draft>",
        new WindowBounds(0, 0, 800, 600),
        ProcessIntegrityLevel.Medium,
        [1, 2, 3],
        Now.ToUnixTimeMilliseconds());

    private static SelectionSnapshot EditableSelection(ForegroundTargetSnapshot target) => new(
        "周三下午可以吗？",
        SelectionAcquisitionSource.UiAutomation,
        target,
        [1, 2, 3],
        [new SelectionRangeSnapshot(
            0,
            "周三下午可以吗？",
            [new WindowBounds(10, 10, 200, 30)],
            "你好，",
            "谢谢")],
        SelectionEditability.Editable,
        true,
        Now.ToUnixTimeMilliseconds());

    private sealed class MockAsrProvider(MockAsrSession session) : IDictationAsrProvider
    {
        public AsrProviderAvailability Availability => AsrProviderAvailability.Ready;

        public ValueTask<IDictationAsrSession> CreateSessionAsync(
            Guid generation,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult<IDictationAsrSession>(session);
        }
    }

    private sealed class MockAsrSession(string finalText, List<string> order)
        : IDictationAsrSession
    {
        public event EventHandler<AsrPartialResult>? PartialReceived;
        public event EventHandler<AsrFinalResult>? FinalReceived;
        public event EventHandler<VoxFlowError>? Failed
        {
            add { }
            remove { }
        }

        public int PushedFrames { get; private set; }

        public ValueTask StartAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            order.Add("asr.start");
            PartialReceived?.Invoke(this, new AsrPartialResult("把回复写入", 1));
            return ValueTask.CompletedTask;
        }

        public ValueTask PushAudioAsync(
            ReadOnlyMemory<byte> pcmS16LittleEndian,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Assert.NotEmpty(pcmS16LittleEndian.ToArray());
            PushedFrames++;
            order.Add("asr.audio");
            return ValueTask.CompletedTask;
        }

        public ValueTask FinishAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            order.Add("asr.final");
            FinalReceived?.Invoke(this, new AsrFinalResult(finalText));
            return ValueTask.CompletedTask;
        }

        public ValueTask CancelAsync(CancellationToken cancellationToken) =>
            ValueTask.CompletedTask;

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class MockAudioCapture(List<string> order) : IDictationAudioCapture
    {
        public int StartCalls { get; private set; }
        public int StopCalls { get; private set; }

        public async ValueTask StartAsync(
            Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> onFrame,
            CancellationToken cancellationToken)
        {
            StartCalls++;
            order.Add("audio.start");
            await onFrame(new byte[3_200], cancellationToken);
        }

        public ValueTask StopAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            StopCalls++;
            order.Add("audio.stop");
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FixedTargetProvider(ForegroundTargetSnapshot target)
        : IAgentComposeTargetSnapshotProvider
    {
        public ForegroundTargetSnapshot? Capture() => target;
    }

    private sealed class FixedContextReader(SelectionSnapshot selection) : IAgentContextReader
    {
        public Task<AgentContextReadResult> ReadAsync(
            ForegroundTargetSnapshot target,
            CancellationToken cancellationToken) => Task.FromResult(new AgentContextReadResult(
            selection,
            "现有输入",
            "普通窗口上下文"));
    }

    private sealed class FixedLlmResolver : IDefaultLlmProviderResolver
    {
        public ValueTask<LlmProviderClientConfiguration?> ResolveDefaultAsync(
            CancellationToken cancellationToken) => ValueTask.FromResult<LlmProviderClientConfiguration?>(new(
            "provider",
            new Uri("https://example.test/v1"),
            "model",
            "secret",
            0.2,
            TimeSpan.FromSeconds(30)));
    }

    private sealed class CapturingSidecarFactory(string script)
        : IBuiltinAgentProcessSessionFactory
    {
        private readonly CapturingSidecarSession session = new(script);

        public BuiltinAgentSidecarRunRequest? Request { get; private set; }
        public string ToolResultsWritten => session.WrittenInput;

        public Task<IBuiltinAgentProcessSession> StartAsync(
            BuiltinAgentSidecarRunRequest request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Request = request;
            return Task.FromResult<IBuiltinAgentProcessSession>(session);
        }
    }

    private sealed class CapturingSidecarSession(string script)
        : IBuiltinAgentProcessSession
    {
        private readonly StringReader output = new(script);
        private readonly StringReader error = new(string.Empty);
        private readonly StringWriter input = new(new StringBuilder());

        public TextReader StandardOutput => output;
        public TextReader StandardError => error;
        public TextWriter StandardInput => input;
        public string WrittenInput => input.ToString();

        public Task<int> WaitForExitAsync(
            CancellationToken cancellationToken,
            TimeSpan? timeout = null) => Task.FromResult(0);

        public Task<BuiltinAgentStderrSummary> DrainStandardErrorAsync(
            CancellationToken cancellationToken) => Task.FromResult(
            new BuiltinAgentStderrSummary(false, false));

        public Task CancelAsync() => Task.CompletedTask;

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class FixedTextFieldFactory(CapturingTextField field)
        : IAgentTextFieldGatewayFactory
    {
        public IAgentTextFieldGateway Create(SelectionSnapshot? selection) => field;
    }

    private sealed class CapturingTextField : IAgentTextFieldGateway
    {
        public List<string> Inserted { get; } = [];

        public Task<AgentTextFieldWriteStatus> InsertAsync(
            string text,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Inserted.Add(text);
            return Task.FromResult(AgentTextFieldWriteStatus.Succeeded);
        }

        public Task<AgentTextFieldWriteStatus> ReplaceSelectionAsync(
            string text,
            CancellationToken cancellationToken) => Task.FromResult(
            AgentTextFieldWriteStatus.Succeeded);
    }

    private sealed class CapturingAgentClipboard : IAgentOutputClipboard
    {
        public string? Text { get; private set; }

        public bool TryCopy(string text)
        {
            Text = text;
            return true;
        }
    }

    private sealed class CapturingSummary : IAgentOutputSummaryPresenter
    {
        public string? Text { get; private set; }
        public void ShowSummary(string? text) => Text = text;
    }

    private sealed class DiscardingOutput : IDictationOutput
    {
        public int Writes { get; private set; }
        public string? LastText { get; private set; }

        public ValueTask<OutputResult> WriteAsync(
            string text,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Writes++;
            LastText = text;
            return ValueTask.FromResult(new OutputResult(OutputResultKind.Copied));
        }
    }

    private sealed class DiscardingHistory : IDictationHistorySink
    {
        public ValueTask SaveAsync(
            DictationHistoryDraft draft,
            CancellationToken cancellationToken) => ValueTask.CompletedTask;
    }

    private sealed class CapturingProgress : IDictationProgressSink
    {
        public void Publish(DictationProgressUpdate update) { }
    }
}
