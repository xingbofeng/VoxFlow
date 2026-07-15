using System.Globalization;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class OutputFailurePresentationTests
{
    [Theory]
    [InlineData("en", "Text could not be inserted into an administrator app. Restart VoxFlow as administrator and try again. The result was copied.")]
    [InlineData("zh-Hans", "无法向管理员应用输入文本。请以管理员身份重启 VoxFlow 后重试。结果已复制。")]
    [InlineData("zh-Hant", "無法向系統管理員應用程式輸入文字。請以系統管理員身分重新啟動 VoxFlow 後再試。結果已複製。")]
    [InlineData("ja", "管理者権限のアプリにテキストを入力できませんでした。VoxFlow を管理者として再起動してから、もう一度お試しください。結果はコピーされました。")]
    [InlineData("ko", "관리자 권한 앱에 텍스트를 입력할 수 없습니다. VoxFlow를 관리자 권한으로 다시 시작한 후 다시 시도하세요. 결과가 복사되었습니다.")]
    public void Permission_denied_has_readable_localized_restart_as_administrator_guidance(
        string cultureName,
        string expectedMessage)
    {
        var result = new OutputResult(
            OutputResultKind.PermissionDenied,
            VoxFlowErrorCode.InputPermissionDenied);

        var presentation = OutputFailurePresentation.From(
            result,
            CultureInfo.GetCultureInfo(cultureName));

        Assert.Equal(OutputRecoveryAction.RestartAsAdministrator, presentation.RecoveryAction);
        Assert.Equal(expectedMessage, presentation.Message);
    }

    [Theory]
    [InlineData(VoxFlowErrorCode.AsrNotConfigured, null, OutputRecoveryAction.OpenModels)]
    [InlineData(VoxFlowErrorCode.MicrophonePermissionDenied, null, OutputRecoveryAction.OpenMicrophonePrivacy)]
    [InlineData(VoxFlowErrorCode.ProviderFailure, AsrProviderId.TencentCloud, OutputRecoveryAction.RetryProvider)]
    [InlineData(VoxFlowErrorCode.NativeRuntimeFailure, AsrProviderId.Qwen, OutputRecoveryAction.RetryQwen)]
    [InlineData(VoxFlowErrorCode.TargetChanged, null, OutputRecoveryAction.None)]
    public void Failures_offer_the_safe_recovery_for_the_actual_failed_boundary(
        VoxFlowErrorCode code,
        AsrProviderId? provider,
        OutputRecoveryAction expectedAction)
    {
        var presentation = OutputFailurePresentation.From(
            new VoxFlowError(code, provider),
            llmFallback: false,
            CultureInfo.GetCultureInfo("en"));

        Assert.Equal(expectedAction, presentation.RecoveryAction);
        Assert.True(presentation.CanCopyDiagnostics);
        Assert.False(presentation.IsFallback);
        Assert.False(string.IsNullOrWhiteSpace(presentation.Message));
    }

    [Fact]
    public void LLM_failure_explains_that_original_ASR_text_was_kept_without_retrying_another_provider()
    {
        var presentation = OutputFailurePresentation.From(
            new VoxFlowError(VoxFlowErrorCode.ProviderFailure),
            llmFallback: true,
            CultureInfo.GetCultureInfo("en"));

        Assert.Equal(OutputRecoveryAction.None, presentation.RecoveryAction);
        Assert.True(presentation.IsFallback);
        Assert.Contains("original recognized text", presentation.Message);
        Assert.True(presentation.CanCopyDiagnostics);
    }
}
