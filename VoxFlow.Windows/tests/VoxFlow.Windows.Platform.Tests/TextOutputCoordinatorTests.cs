using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Output;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class TextOutputCoordinatorTests
{
    [Theory]
    [InlineData(InputIntegrityRelation.Higher, OutputResultKind.PermissionDenied)]
    [InlineData(InputIntegrityRelation.EqualOrLower, OutputResultKind.InjectionFailed)]
    [InlineData(InputIntegrityRelation.Unknown, OutputResultKind.InjectionFailed)]
    public void Failed_send_is_permission_denied_only_when_uipi_relation_is_known_higher(
        InputIntegrityRelation relation,
        OutputResultKind expected)
    {
        var result = InputFailureClassifier.Classify(relation);

        Assert.Equal(expected, result.Kind);
        Assert.Equal(
            expected == OutputResultKind.PermissionDenied
                ? VoxFlowErrorCode.InputPermissionDenied
                : VoxFlowErrorCode.InputInjectionFailure,
            result.ErrorCode);
    }

    [Fact]
    public async Task Uipi_aware_injector_reclassifies_native_failure_against_current_target_pid()
    {
        var target = new ForegroundTargetIdentity(
            77,
            @"C:\Admin\admin.exe",
            new nint(0x777),
            "Administrator console");
        var inner = new StubTextOutputInjector(
            new OutputResult(
                OutputResultKind.InjectionFailed,
                VoxFlowErrorCode.InputInjectionFailure));
        var integrity = new StubInputIntegrityProbe(InputIntegrityRelation.Higher);
        var injector = new UipiAwareTextOutputInjector(
            inner,
            new SequenceForegroundTargetProvider(target, target),
            integrity);

        var result = await injector.InjectAsync("text", CancellationToken.None);

        Assert.Equal(OutputResultKind.PermissionDenied, result.Kind);
        Assert.Equal(77, integrity.TargetProcessId);
    }

    [Fact]
    public async Task Uipi_permission_failure_copies_text_and_preserves_admin_recovery_result()
    {
        var injector = new StubTextOutputInjector(
            new OutputResult(
                OutputResultKind.PermissionDenied,
                VoxFlowErrorCode.InputPermissionDenied));
        var clipboard = new CapturingOutputClipboardCopier();
        var output = new WindowsTextOutputCoordinator(injector, clipboard);

        var result = await output.WriteAsync("administrator target", CancellationToken.None);

        Assert.Equal(OutputResultKind.PermissionDenied, result.Kind);
        Assert.Equal(VoxFlowErrorCode.InputPermissionDenied, result.ErrorCode);
        Assert.Equal("administrator target", clipboard.Text);
    }

    [Fact]
    public async Task Ordinary_injection_failure_copies_text_and_keeps_non_permission_classification()
    {
        var injector = new StubTextOutputInjector(
            new OutputResult(
                OutputResultKind.InjectionFailed,
                VoxFlowErrorCode.InputInjectionFailure));
        var clipboard = new CapturingOutputClipboardCopier();
        var output = new WindowsTextOutputCoordinator(injector, clipboard);

        var result = await output.WriteAsync("fallback text", CancellationToken.None);

        Assert.Equal(OutputResultKind.InjectionFailed, result.Kind);
        Assert.Equal(VoxFlowErrorCode.InputInjectionFailure, result.ErrorCode);
        Assert.Equal("fallback text", clipboard.Text);
    }

    [Fact]
    public async Task Cancellation_observed_after_failed_injection_never_copies_text()
    {
        using var cancellation = new CancellationTokenSource();
        var injector = new StubTextOutputInjector(
            new OutputResult(
                OutputResultKind.InjectionFailed,
                VoxFlowErrorCode.InputInjectionFailure),
            beforeReturn: cancellation.Cancel);
        var clipboard = new CapturingOutputClipboardCopier();
        var output = new WindowsTextOutputCoordinator(injector, clipboard);

        var result = await output.WriteAsync("must not copy", cancellation.Token);

        Assert.Equal(OutputResultKind.Cancelled, result.Kind);
        Assert.Null(clipboard.Text);
    }

    [Fact]
    public async Task Failed_fallback_copy_is_reported_as_clipboard_failure()
    {
        var injector = new StubTextOutputInjector(
            new OutputResult(
                OutputResultKind.InjectionFailed,
                VoxFlowErrorCode.InputInjectionFailure));
        var clipboard = new CapturingOutputClipboardCopier(succeeds: false);
        var output = new WindowsTextOutputCoordinator(injector, clipboard);

        var result = await output.WriteAsync("copy also fails", CancellationToken.None);

        Assert.Equal(OutputResultKind.CopyFailed, result.Kind);
        Assert.Equal(VoxFlowErrorCode.ClipboardFailure, result.ErrorCode);
    }

    [Fact]
    public async Task Changed_foreground_target_is_copied_without_calling_any_injector()
    {
        var original = new ForegroundTargetIdentity(
            10,
            @"C:\Editor\editor.exe",
            new nint(0x100),
            "Document A");
        var changed = new ForegroundTargetIdentity(
            20,
            @"C:\Browser\browser.exe",
            new nint(0x200),
            "New tab");
        var targetProvider = new SequenceForegroundTargetProvider(original, changed);
        var injector = new StubTextOutputInjector(
            new OutputResult(OutputResultKind.Inserted));
        var clipboard = new CapturingOutputClipboardCopier();
        var output = new WindowsTextOutputCoordinator(
            injector,
            clipboard,
            new ForegroundTargetOutputGuard(targetProvider));
        output.CaptureOriginalTarget();

        var result = await output.WriteAsync("safe copy", CancellationToken.None);

        Assert.Equal(OutputResultKind.TargetChanged, result.Kind);
        Assert.Equal("safe copy", clipboard.Text);
        Assert.Equal(0, injector.CallCount);
    }

    [Fact]
    public async Task Cancellation_observed_during_target_check_never_copies_text()
    {
        using var cancellation = new CancellationTokenSource();
        var original = new ForegroundTargetIdentity(
            10,
            @"C:\Editor\editor.exe",
            new nint(0x100),
            "Document A");
        var changed = new ForegroundTargetIdentity(
            20,
            @"C:\Browser\browser.exe",
            new nint(0x200),
            "New tab");
        var targetProvider = new SequenceForegroundTargetProvider(
            original,
            changed,
            cancellation.Cancel);
        var clipboard = new CapturingOutputClipboardCopier();
        var output = new WindowsTextOutputCoordinator(
            new StubTextOutputInjector(new OutputResult(OutputResultKind.Inserted)),
            clipboard,
            new ForegroundTargetOutputGuard(targetProvider));
        output.CaptureOriginalTarget();

        var result = await output.WriteAsync("must not copy", cancellation.Token);

        Assert.Equal(OutputResultKind.Cancelled, result.Kind);
        Assert.Null(clipboard.Text);
    }

    private sealed class StubTextOutputInjector(
        OutputResult result,
        Action? beforeReturn = null) : ITextOutputInjector
    {
        public int CallCount { get; private set; }

        public ValueTask<OutputResult> InjectAsync(
            string text,
            CancellationToken cancellationToken)
        {
            CallCount++;
            beforeReturn?.Invoke();
            return ValueTask.FromResult(result);
        }
    }

    private sealed class CapturingOutputClipboardCopier(
        bool succeeds = true) : IOutputClipboardCopier
    {
        public string? Text { get; private set; }

        public bool TryCopy(string text)
        {
            Text = text;
            return succeeds;
        }
    }

    private sealed class SequenceForegroundTargetProvider(
        ForegroundTargetIdentity original,
        ForegroundTargetIdentity current,
        Action? beforeLiveness = null) : IForegroundTargetProvider
    {
        private int captureCount;

        public ForegroundTargetIdentity? CaptureCurrent() =>
            Interlocked.Increment(ref captureCount) == 1 ? original : current;

        public ForegroundTargetLiveness GetLiveness(ForegroundTargetIdentity target)
        {
            beforeLiveness?.Invoke();
            return ForegroundTargetLiveness.Exists;
        }
    }

    private sealed class StubInputIntegrityProbe(
        InputIntegrityRelation relation) : IInputIntegrityProbe
    {
        public int? TargetProcessId { get; private set; }

        public InputIntegrityRelation CompareWithCurrentProcess(int targetProcessId)
        {
            TargetProcessId = targetProcessId;
            return relation;
        }
    }
}
