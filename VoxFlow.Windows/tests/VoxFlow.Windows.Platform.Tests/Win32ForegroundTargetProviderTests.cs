using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class Win32ForegroundTargetProviderTests
{
    private const string EditorPath = @"C:\Apps\Editor\editor.exe";

    [Fact]
    public void Capture_current_reads_handle_pid_executable_path_and_diagnostic_title()
    {
        var api = new FakeWin32ForegroundTargetApi
        {
            ForegroundWindow = new nint(0x1234),
            ForegroundProcessId = 42,
            ProcessPath = EditorPath,
            WindowTitle = "Document A",
        };
        var provider = new Win32ForegroundTargetProvider(api);

        var target = provider.CaptureCurrent();

        Assert.Equal(
            new ForegroundTargetIdentity(42, EditorPath, new nint(0x1234), "Document A"),
            target);
        Assert.Equal(1, api.WindowTextReadCount);
    }

    [Theory]
    [InlineData(ForegroundCaptureFailure.NoWindow)]
    [InlineData(ForegroundCaptureFailure.ProcessLookup)]
    [InlineData(ForegroundCaptureFailure.ProcessPath)]
    [InlineData(ForegroundCaptureFailure.NativeException)]
    public void Capture_current_fails_closed_without_leaking_native_or_process_errors(
        ForegroundCaptureFailure failure)
    {
        var api = new FakeWin32ForegroundTargetApi
        {
            ForegroundWindow = failure == ForegroundCaptureFailure.NoWindow
                ? nint.Zero
                : new nint(0x1234),
            ForegroundProcessId = failure == ForegroundCaptureFailure.ProcessLookup ? 0 : 42,
            ProcessPath = failure == ForegroundCaptureFailure.ProcessPath ? null : EditorPath,
            WindowTitle = "Document A",
            ThrowOnForegroundWindow = failure == ForegroundCaptureFailure.NativeException,
        };
        var provider = new Win32ForegroundTargetProvider(api);

        var target = provider.CaptureCurrent();

        Assert.Null(target);
    }

    [Fact]
    public void Missing_or_inaccessible_title_does_not_discard_a_valid_target()
    {
        var api = new FakeWin32ForegroundTargetApi
        {
            ForegroundWindow = new nint(0x1234),
            ForegroundProcessId = 42,
            ProcessPath = EditorPath,
            ThrowOnWindowText = true,
        };
        var provider = new Win32ForegroundTargetProvider(api);

        var target = provider.CaptureCurrent();

        Assert.NotNull(target);
        Assert.Equal(string.Empty, target.WindowTitle);
    }

    [Fact]
    public void Default_provider_can_probe_the_real_win32_boundary_without_throwing()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        ForegroundTargetIdentity? target = null;
        var exception = Record.Exception(
            () => target = new Win32ForegroundTargetProvider().CaptureCurrent());

        Assert.Null(exception);
        if (target is not null)
        {
            Assert.True(target.ProcessId > 0);
            Assert.NotEqual(nint.Zero, target.WindowHandle);
            Assert.False(string.IsNullOrWhiteSpace(target.ProcessPath));
        }
    }

    [Theory]
    [InlineData(@"c:\apps\EDITOR\EDITOR.EXE", ForegroundTargetLiveness.Exists)]
    [InlineData(@"C:\Apps\Browser\browser.exe", ForegroundTargetLiveness.Missing)]
    [InlineData(null, ForegroundTargetLiveness.Missing)]
    public void Liveness_rejects_missing_or_reused_process_ids(
        string? currentProcessPath,
        ForegroundTargetLiveness expected)
    {
        var api = new FakeWin32ForegroundTargetApi
        {
            ProcessPath = currentProcessPath,
        };
        var provider = new Win32ForegroundTargetProvider(api);
        var original = new ForegroundTargetIdentity(
            42,
            EditorPath,
            new nint(0x1234),
            "Document A");

        Assert.Equal(expected, provider.GetLiveness(original));
    }

    [Theory]
    [InlineData(ProcessPathLookupStatus.Unavailable)]
    [InlineData(ProcessPathLookupStatus.Found)]
    public void Unreadable_or_exceptional_process_liveness_is_unknown(
        ProcessPathLookupStatus lookupStatus)
    {
        var api = new FakeWin32ForegroundTargetApi
        {
            ProcessPathStatus = lookupStatus,
            ThrowOnProcessPath = lookupStatus == ProcessPathLookupStatus.Found,
        };
        var provider = new Win32ForegroundTargetProvider(api);
        var original = new ForegroundTargetIdentity(
            42,
            EditorPath,
            new nint(0x1234),
            "Document A");

        Assert.Equal(ForegroundTargetLiveness.Unknown, provider.GetLiveness(original));
    }

    [Fact]
    public void Confirmed_process_exit_is_missing_not_unknown()
    {
        var api = new FakeWin32ForegroundTargetApi
        {
            ProcessPathStatus = ProcessPathLookupStatus.Missing,
        };
        var provider = new Win32ForegroundTargetProvider(api);
        var original = new ForegroundTargetIdentity(
            42,
            EditorPath,
            new nint(0x1234),
            "Document A");

        Assert.Equal(ForegroundTargetLiveness.Missing, provider.GetLiveness(original));
    }

    [Fact]
    public void Completion_guard_recaptures_target_and_returns_copy_with_target_changed_result()
    {
        var original = new ForegroundTargetIdentity(
            42,
            EditorPath,
            new nint(0x1234),
            "Document A");
        var changed = original with { WindowHandle = new nint(0x5678), WindowTitle = "Document B" };
        var provider = new FakeForegroundTargetProvider(
            original,
            changed,
            ForegroundTargetLiveness.Exists);
        var guard = new ForegroundTargetOutputGuard(provider);

        var captured = guard.CaptureOriginal();
        var decision = guard.DecideBeforeOutput(captured);

        Assert.Equal(2, provider.CaptureCount);
        Assert.Equal(TargetAwareOutputAction.Copy, decision.Action);
        Assert.Equal(ForegroundTargetComparison.TargetChanged, decision.Comparison);
        Assert.Equal(
            new OutputResult(OutputResultKind.TargetChanged, VoxFlowErrorCode.TargetChanged),
            decision.Result);
    }

    [Fact]
    public void Completion_guard_does_not_report_target_changed_when_original_process_is_gone()
    {
        var original = new ForegroundTargetIdentity(
            42,
            EditorPath,
            new nint(0x1234),
            "Document A");
        var unrelated = new ForegroundTargetIdentity(
            77,
            @"C:\Apps\Browser\browser.exe",
            new nint(0x5678),
            "New tab");
        var provider = new FakeForegroundTargetProvider(
            original,
            unrelated,
            ForegroundTargetLiveness.Missing);
        var guard = new ForegroundTargetOutputGuard(provider);

        var decision = guard.DecideBeforeOutput(guard.CaptureOriginal());

        Assert.Equal(TargetAwareOutputAction.Inject, decision.Action);
        Assert.Equal(ForegroundTargetComparison.OriginalNoLongerExists, decision.Comparison);
        Assert.Null(decision.Result);
    }

    [Fact]
    public void Inaccessible_original_process_liveness_fails_closed_to_copy()
    {
        var original = new ForegroundTargetIdentity(
            42,
            EditorPath,
            new nint(0x1234),
            "Document A");
        var api = new FakeWin32ForegroundTargetApi
        {
            ForegroundWindow = new nint(0x5678),
            ForegroundProcessId = 77,
            ProcessPathResolver = processId => processId == original.ProcessId
                ? throw new UnauthorizedAccessException("process is protected")
                : ProcessPathLookup.Found(@"C:\Apps\Browser\browser.exe"),
            WindowTitle = "New tab",
        };
        var guard = new ForegroundTargetOutputGuard(
            new Win32ForegroundTargetProvider(api));

        var decision = guard.DecideBeforeOutput(original);

        Assert.Equal(TargetAwareOutputAction.Copy, decision.Action);
        Assert.Equal(
            ForegroundTargetComparison.OriginalLivenessUnknown,
            decision.Comparison);
        Assert.Equal(OutputResultKind.TargetChanged, decision.Result?.Kind);
    }

    [Fact]
    public void Missing_original_capture_falls_back_to_copy_without_probing_process_liveness()
    {
        var provider = new FakeForegroundTargetProvider(
            first: null,
            second: null,
            ForegroundTargetLiveness.Exists);
        var guard = new ForegroundTargetOutputGuard(provider);

        var decision = guard.DecideBeforeOutput(guard.CaptureOriginal());

        Assert.Equal(1, provider.CaptureCount);
        Assert.Equal(0, provider.LivenessReadCount);
        Assert.Equal(TargetAwareOutputAction.Copy, decision.Action);
        Assert.Equal(ForegroundTargetComparison.OriginalUnavailable, decision.Comparison);
        Assert.Equal(OutputResultKind.TargetChanged, decision.Result?.Kind);
    }

    public enum ForegroundCaptureFailure
    {
        NoWindow,
        ProcessLookup,
        ProcessPath,
        NativeException,
    }

    private sealed class FakeWin32ForegroundTargetApi : IWin32ForegroundTargetApi
    {
        public nint ForegroundWindow { get; init; }

        public int ForegroundProcessId { get; init; }

        public string? ProcessPath { get; init; }

        public ProcessPathLookupStatus? ProcessPathStatus { get; init; }

        public Func<int, ProcessPathLookup>? ProcessPathResolver { get; init; }

        public bool ThrowOnProcessPath { get; init; }

        public string WindowTitle { get; init; } = string.Empty;

        public bool ThrowOnForegroundWindow { get; init; }

        public bool ThrowOnWindowText { get; init; }

        public int WindowTextReadCount { get; private set; }

        public nint GetForegroundWindow()
        {
            if (ThrowOnForegroundWindow)
            {
                throw new InvalidOperationException("native foreground lookup failed");
            }

            return ForegroundWindow;
        }

        public bool TryGetWindowProcessId(nint windowHandle, out int processId)
        {
            processId = ForegroundProcessId;
            return processId > 0;
        }

        public ProcessPathLookup LookupProcessPath(int processId)
        {
            if (ThrowOnProcessPath)
            {
                throw new UnauthorizedAccessException("process path unavailable");
            }

            if (ProcessPathResolver is not null)
            {
                return ProcessPathResolver(processId);
            }

            return ProcessPathStatus switch
            {
                ProcessPathLookupStatus.Missing => ProcessPathLookup.Missing,
                ProcessPathLookupStatus.Unavailable => ProcessPathLookup.Unavailable,
                ProcessPathLookupStatus.Found when !string.IsNullOrWhiteSpace(ProcessPath) =>
                    ProcessPathLookup.Found(ProcessPath),
                ProcessPathLookupStatus.Found => ProcessPathLookup.Unavailable,
                _ when string.IsNullOrWhiteSpace(ProcessPath) => ProcessPathLookup.Missing,
                _ => ProcessPathLookup.Found(ProcessPath),
            };
        }

        public string GetWindowText(nint windowHandle)
        {
            WindowTextReadCount++;
            if (ThrowOnWindowText)
            {
                throw new InvalidOperationException("window title unavailable");
            }

            return WindowTitle;
        }
    }

    private sealed class FakeForegroundTargetProvider : IForegroundTargetProvider
    {
        private readonly ForegroundTargetIdentity? first;
        private readonly ForegroundTargetIdentity? second;
        private readonly ForegroundTargetLiveness originalLiveness;

        public FakeForegroundTargetProvider(
            ForegroundTargetIdentity? first,
            ForegroundTargetIdentity? second,
            ForegroundTargetLiveness originalLiveness)
        {
            this.first = first;
            this.second = second;
            this.originalLiveness = originalLiveness;
        }

        public int CaptureCount { get; private set; }

        public int LivenessReadCount { get; private set; }

        public ForegroundTargetIdentity? CaptureCurrent()
        {
            CaptureCount++;
            return CaptureCount == 1 ? first : second;
        }

        public ForegroundTargetLiveness GetLiveness(ForegroundTargetIdentity target)
        {
            LivenessReadCount++;
            return originalLiveness;
        }
    }
}
