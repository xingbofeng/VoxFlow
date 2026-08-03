using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentComposeDictationBridgeTests
{
    [Fact]
    public async Task Frozen_context_is_captured_before_recording_and_sidecar_starts_only_from_final_text()
    {
        var reader = new CapturingReader();
        var capture = new AgentComposeContextCapture(new FixedTargetProvider(Target()), new AgentContextPipeline(reader));
        var executor = new CapturingExecutor();
        var root = Path.Combine(Path.GetTempPath(), "voxflow-agent-bridge-" + Guid.NewGuid().ToString("N"));
        try
        {
            capture.CaptureOriginalTarget();
            var workspaces = new AgentSessionWorkspaceRetentionService(
                new FileSystemAgentSessionWorkspaceStore(root),
                TimeProvider.System);
            var processor = new AgentComposeDictationPostProcessor(capture, executor,
                taskId => Path.Combine(root, taskId),
                output: new AgentComposeOutputCoordinator(new Copy(), new Summary()),
                sessionWorkspaces: workspaces);
            var progress = new List<string>();

            var result = await processor.ProcessAsync("draft a reply", new Progress<string>(progress.Add), CancellationToken.None);

            Assert.Equal("done", result);
            Assert.Equal("draft a reply", executor.Instruction);
            Assert.Equal("selected context", executor.Context?.SelectedText);
            Assert.True(Directory.Exists(executor.Workspace!));
            Assert.True(reader.Read);
            Assert.True(File.Exists(Path.Combine(executor.Workspace!, "result.md")));
            Assert.False(Directory.Exists(Path.Combine(executor.Workspace!, "screenshots")));
            Assert.False(Directory.Exists(Path.Combine(executor.Workspace!, "tmp")));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task Sidecar_failure_is_not_transformed_into_dictation_text()
    {
        var capture = new AgentComposeContextCapture(new FixedTargetProvider(Target()), new AgentContextPipeline(new CapturingReader()));
        capture.CaptureOriginalTarget();
        var processor = new AgentComposeDictationPostProcessor(capture, new FailingExecutor(), taskId => Path.Combine(Path.GetTempPath(), taskId));

        await Assert.ThrowsAsync<InvalidOperationException>(() => processor.ProcessAsync("do work", new Progress<string>(), CancellationToken.None).AsTask());
    }

    [Fact]
    public async Task Cancelled_sidecar_outcome_remains_cancellation_not_a_failed_dictation()
    {
        var capture = new AgentComposeContextCapture(new FixedTargetProvider(Target()), new AgentContextPipeline(new CapturingReader()));
        capture.CaptureOriginalTarget();
        var processor = new AgentComposeDictationPostProcessor(
            capture,
            new CancelledExecutor(),
            taskId => Path.Combine(Path.GetTempPath(), taskId));

        await Assert.ThrowsAsync<OperationCanceledException>(() =>
            processor.ProcessAsync("cancel me", new Progress<string>(), CancellationToken.None).AsTask());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Ephemeral_workspace_content_is_removed_after_failure_or_cancellation(
        bool cancelled)
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-agent-cleanup-" + Guid.NewGuid().ToString("N"));
        try
        {
            var capture = new AgentComposeContextCapture(
                new FixedTargetProvider(Target()),
                new AgentContextPipeline(new CapturingReader()));
            capture.CaptureOriginalTarget();
            var workspaces = new AgentSessionWorkspaceRetentionService(
                new FileSystemAgentSessionWorkspaceStore(root),
                TimeProvider.System);
            var processor = new AgentComposeDictationPostProcessor(
                capture,
                new EphemeralOutcomeExecutor(cancelled),
                taskId => Path.Combine(root, taskId),
                sessionWorkspaces: workspaces);

            if (cancelled)
            {
                await Assert.ThrowsAsync<OperationCanceledException>(() =>
                    processor.ProcessAsync("cancel", new Progress<string>(), CancellationToken.None).AsTask());
            }
            else
            {
                await Assert.ThrowsAsync<InvalidOperationException>(() =>
                    processor.ProcessAsync("fail", new Progress<string>(), CancellationToken.None).AsTask());
            }

            var workspace = Path.Combine(root, capture.TaskId);
            Assert.False(Directory.Exists(Path.Combine(workspace, "screenshots")));
            Assert.False(Directory.Exists(Path.Combine(workspace, "tmp")));
            Assert.Equal("artifact", File.ReadAllText(Path.Combine(workspace, "result.md")));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); }
    }

    private static ForegroundTargetSnapshot Target() => new(1, 2, "notepad.exe", "draft", new WindowBounds(0, 0, 20, 20), ProcessIntegrityLevel.Medium, [1], 1);

    private sealed class FixedTargetProvider(ForegroundTargetSnapshot target) : IAgentComposeTargetSnapshotProvider
    {
        public ForegroundTargetSnapshot? Capture() => target;
    }

    private sealed class CapturingReader : IAgentContextReader
    {
        public bool Read { get; private set; }
        public Task<AgentContextReadResult> ReadAsync(ForegroundTargetSnapshot target, CancellationToken cancellationToken)
        {
            Read = true;
            return Task.FromResult(new AgentContextReadResult(
                new SelectionSnapshot("selected context", SelectionAcquisitionSource.UiAutomation, target, [1], [new SelectionRangeSnapshot(0, "selected context", [new WindowBounds(0, 0, 1, 1)], null, null)], SelectionEditability.ReadOnly, true, 1),
                null,
                null));
        }
    }

    private sealed class CapturingExecutor : IAgentComposeExecutionService
    {
        public string? Instruction { get; private set; }
        public AgentContextSnapshot? Context { get; private set; }
        public string? Workspace { get; private set; }
        public async Task<AgentComposeExecutionResult> ExecuteWithBuiltinToolsAsync(string taskId, string voiceInstruction, AgentContextSnapshot context, string workspaceDirectory, IHistoryStore? history, Func<BuiltinAgentSidecarEvent, Task> onEvent, CancellationToken cancellationToken)
        {
            Instruction = voiceInstruction; Context = context; Workspace = workspaceDirectory;
            Directory.CreateDirectory(Path.Combine(workspaceDirectory, "screenshots"));
            Directory.CreateDirectory(Path.Combine(workspaceDirectory, "tmp"));
            File.WriteAllText(Path.Combine(workspaceDirectory, "screenshots", "capture.png"), "pixels");
            File.WriteAllText(Path.Combine(workspaceDirectory, "tmp", "request.json"), "transient");
            File.WriteAllText(Path.Combine(workspaceDirectory, "result.md"), "artifact");
            await onEvent(new BuiltinAgentSidecarEvent("modelDelta", text: "thinking"));
            await onEvent(new BuiltinAgentSidecarEvent("turnCompleted", summary: "done"));
            return new(AgentComposeExecutionStatus.Completed);
        }
    }

    private sealed class FailingExecutor : IAgentComposeExecutionService
    {
        public Task<AgentComposeExecutionResult> ExecuteWithBuiltinToolsAsync(string taskId, string voiceInstruction, AgentContextSnapshot context, string workspaceDirectory, IHistoryStore? history, Func<BuiltinAgentSidecarEvent, Task> onEvent, CancellationToken cancellationToken) => Task.FromResult(new AgentComposeExecutionResult(AgentComposeExecutionStatus.Failed));
    }

    private sealed class CancelledExecutor : IAgentComposeExecutionService
    {
        public Task<AgentComposeExecutionResult> ExecuteWithBuiltinToolsAsync(string taskId, string voiceInstruction, AgentContextSnapshot context, string workspaceDirectory, IHistoryStore? history, Func<BuiltinAgentSidecarEvent, Task> onEvent, CancellationToken cancellationToken) => Task.FromResult(
            new AgentComposeExecutionResult(
                AgentComposeExecutionStatus.Failed,
                new BuiltinAgentSidecarRunOutcome(false, "cancelled", null, new BuiltinAgentStderrSummary(false, false))));
    }

    private sealed class EphemeralOutcomeExecutor(bool cancelled) : IAgentComposeExecutionService
    {
        public Task<AgentComposeExecutionResult> ExecuteWithBuiltinToolsAsync(
            string taskId,
            string voiceInstruction,
            AgentContextSnapshot context,
            string workspaceDirectory,
            IHistoryStore? history,
            Func<BuiltinAgentSidecarEvent, Task> onEvent,
            CancellationToken cancellationToken)
        {
            Directory.CreateDirectory(Path.Combine(workspaceDirectory, "screenshots"));
            Directory.CreateDirectory(Path.Combine(workspaceDirectory, "tmp"));
            File.WriteAllText(Path.Combine(workspaceDirectory, "screenshots", "capture.png"), "pixels");
            File.WriteAllText(Path.Combine(workspaceDirectory, "tmp", "request.json"), "transient");
            File.WriteAllText(Path.Combine(workspaceDirectory, "result.md"), "artifact");
            return Task.FromResult(cancelled
                ? new AgentComposeExecutionResult(
                    AgentComposeExecutionStatus.Failed,
                    new BuiltinAgentSidecarRunOutcome(
                        false,
                        "cancelled",
                        null,
                        new BuiltinAgentStderrSummary(false, false)))
                : new AgentComposeExecutionResult(AgentComposeExecutionStatus.Failed));
        }
    }

    private sealed class Copy : IAgentOutputClipboard
    {
        public bool TryCopy(string text) => true;
    }
    private sealed class Summary : IAgentOutputSummaryPresenter
    {
        public void ShowSummary(string? text) { }
    }
}
