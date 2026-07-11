using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class DomainValueObjectTests
{
    [Fact]
    public void Qwen_selection_requires_a_variant_and_cloud_selection_forbids_one()
    {
        var local = new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B);
        var cloud = new AsrSelection(AsrProviderId.TencentCloud, null);

        Assert.Equal(QwenVariant.Qwen06B, local.QwenVariant);
        Assert.Null(cloud.QwenVariant);
        Assert.Throws<ArgumentException>(() =>
            new AsrSelection(AsrProviderId.Qwen, null));
        Assert.Throws<ArgumentException>(() =>
            new AsrSelection(AsrProviderId.Volcengine, QwenVariant.Qwen17B));
    }

    [Theory]
    [InlineData(QwenVariant.Qwen06B, "Qwen 0.6B")]
    [InlineData(QwenVariant.Qwen17B, "Qwen 1.7B")]
    public void Qwen_variant_has_a_stable_display_name(
        QwenVariant variant,
        string expected)
    {
        Assert.Equal(expected, variant.DisplayName());
    }

    [Fact]
    public void Llm_state_distinguishes_missing_disabled_ready_and_failed_configuration()
    {
        var missing = new LlmState(LlmAvailability.NotConfigured, null, null);
        var disabled = new LlmState(LlmAvailability.Disabled, "hunyuan-lite", null);
        var ready = new LlmState(LlmAvailability.Ready, "hunyuan-lite", null);
        var failed = new LlmState(
            LlmAvailability.Failed,
            "hunyuan-lite",
            VoxFlowErrorCode.AuthenticationFailed);

        Assert.Null(missing.Model);
        Assert.Equal("hunyuan-lite", disabled.Model);
        Assert.Equal(LlmAvailability.Ready, ready.Availability);
        Assert.Equal(VoxFlowErrorCode.AuthenticationFailed, failed.ErrorCode);

        Assert.Throws<ArgumentException>(() =>
            new LlmState(LlmAvailability.Ready, " ", null));
        Assert.Throws<ArgumentException>(() =>
            new LlmState(LlmAvailability.Failed, "hunyuan-lite", null));
        Assert.Throws<ArgumentException>(() =>
            new LlmState(
                LlmAvailability.Ready,
                "hunyuan-lite",
                VoxFlowErrorCode.ProviderFailure));
    }

    [Theory]
    [InlineData(OutputResultKind.TargetChanged, VoxFlowErrorCode.TargetChanged)]
    [InlineData(OutputResultKind.PermissionDenied, VoxFlowErrorCode.InputPermissionDenied)]
    [InlineData(OutputResultKind.InjectionFailed, VoxFlowErrorCode.InputInjectionFailure)]
    [InlineData(OutputResultKind.CopyFailed, VoxFlowErrorCode.ClipboardFailure)]
    public void Failed_output_results_require_the_matching_safe_error(
        OutputResultKind kind,
        VoxFlowErrorCode errorCode)
    {
        var result = new OutputResult(kind, errorCode);

        Assert.Equal(errorCode, result.ErrorCode);
        Assert.Throws<ArgumentException>(() =>
            new OutputResult(kind, VoxFlowErrorCode.NetworkFailure));
    }

    [Theory]
    [InlineData(OutputResultKind.Inserted)]
    [InlineData(OutputResultKind.Copied)]
    [InlineData(OutputResultKind.Cancelled)]
    public void Successful_or_cancelled_output_results_forbid_an_error(
        OutputResultKind kind)
    {
        var result = new OutputResult(kind);

        Assert.Null(result.ErrorCode);
        Assert.Throws<ArgumentException>(() =>
            new OutputResult(kind, VoxFlowErrorCode.Unknown));
    }

    [Fact]
    public void History_policy_defaults_to_thirty_days_and_validates_custom_days()
    {
        Assert.Equal(HistoryRetentionMode.RetainForDays, HistoryRetentionPolicy.Default.Mode);
        Assert.Equal(30, HistoryRetentionPolicy.Default.Days);
        Assert.Equal(HistoryRetentionMode.Disabled, HistoryRetentionPolicy.Disabled.Mode);
        Assert.Null(HistoryRetentionPolicy.Disabled.Days);
        Assert.Equal(HistoryRetentionMode.Forever, HistoryRetentionPolicy.Forever.Mode);
        Assert.Equal(90, HistoryRetentionPolicy.ForDays(90).Days);

        Assert.Throws<ArgumentOutOfRangeException>(() => HistoryRetentionPolicy.ForDays(0));
        Assert.Throws<ArgumentException>(() =>
            new HistoryRetentionPolicy(HistoryRetentionMode.Disabled, 30));
    }

    [Fact]
    public void Ui_state_is_Wpf_free_and_rejects_invalid_window_bounds()
    {
        var bounds = new WindowBounds(20, 30, 1260, 720);
        var state = new UiState("monitor-1", bounds, true);

        Assert.Equal(1260, state.MainWindowBounds!.Width);
        Assert.True(state.IsSidebarCollapsed);
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new WindowBounds(0, 0, 0, 720));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new WindowBounds(double.NaN, 0, 1260, 720));
        Assert.Throws<ArgumentException>(() =>
            new UiState(" ", null, false));
    }

    [Theory]
    [InlineData(VoxFlowErrorCode.NetworkFailure, VoxFlowErrorCategory.Network, true)]
    [InlineData(VoxFlowErrorCode.AuthenticationFailed, VoxFlowErrorCategory.Provider, false)]
    [InlineData(VoxFlowErrorCode.MicrophonePermissionDenied, VoxFlowErrorCategory.Permission, false)]
    [InlineData(VoxFlowErrorCode.ClipboardFailure, VoxFlowErrorCategory.Output, true)]
    public void Errors_have_central_safe_classification(
        VoxFlowErrorCode code,
        VoxFlowErrorCategory expectedCategory,
        bool expectedRetryable)
    {
        var classification = new VoxFlowError(code).Classify();

        Assert.Equal(expectedCategory, classification.Category);
        Assert.Equal(expectedRetryable, classification.IsRetryable);
    }
}
