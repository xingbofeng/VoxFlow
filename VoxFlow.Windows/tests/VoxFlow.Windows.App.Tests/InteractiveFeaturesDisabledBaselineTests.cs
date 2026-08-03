using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.App.Tests;

public sealed class InteractiveFeaturesDisabledBaselineTests
{
    [Fact]
    public void Disabled_features_leave_shell_and_tray_ids_at_the_p1_p3_baseline()
    {
        var plan = InteractiveFeatureRegistrationPlan.Create(
            WindowsInteractiveFeatureFlags.Disabled);
        var shell = new MainShellViewModel();
        var tray = TrayMenuProjection.Build(new TrayMenuState(
            RecognitionLanguage.Automatic,
            SelectedAsr: null,
            AsrChoices: [],
            OpenAiConfigured: false,
            OpenAiEnabled: false,
            Agent: new TrayAgentState(
                RuntimeAvailable: false,
                ProviderConfigured: false,
                ConnectionHealthy: false,
                ToolCallingSupported: false,
                DictationPhase.Idle)));

        Assert.Equal(
            [
                ShellRoute.Home,
                ShellRoute.Media,
                ShellRoute.AgentWorkspace,
                ShellRoute.Glossary,
                ShellRoute.WritingStyles,
                ShellRoute.FileTranscription,
                ShellRoute.Notes,
                ShellRoute.Settings,
                ShellRoute.Help,
            ],
            shell.NavigationItems.Select(item => item.Route));
        Assert.Equal(
            [
                "language",
                "language.auto",
                "language.zh-CN",
                "language.en-US",
                "language.ja-JP",
                "language.ko-KR",
                "asr",
                "asr.qwen.0.6b",
                "asr.qwen.1.7b",
                "asr.tencent",
                "asr.aliyun",
                "asr.volcengine",
                "openai",
                "openai.enabled",
                "agent",
                "agent.status.runtimeUnavailable",
                "agent.start",
                "agent.stop",
                "separator.providers",
                "screenshot.start",
                "app.openWindow",
                "app.openSettings",
                "app.openGithub",
                "app.openPermissions",
                "separator.exit",
                "app.exit",
            ],
            tray.Flatten().Select(item => item.Id));
        Assert.Empty(plan.TrayCommandIds);
    }

    [Fact]
    public void Disabled_features_leave_the_existing_right_control_router_unchanged()
    {
        var plan = InteractiveFeatureRegistrationPlan.Create(
            WindowsInteractiveFeatureFlags.Disabled);
        var settings = HotkeyRouteSettings.Default with
        {
            InteractionMode = HotkeyInteractionMode.Toggle,
        };
        var router = new HotkeyInputRouter(settings);
        var key = new LowLevelKeyEvent(
            RightControlKeyClassifier.VirtualKeyRightControl,
            RightControlKeyClassifier.ControlScanCode,
            LowLevelKeyFlags.Extended,
            KeyTransition.Down,
            DateTimeOffset.UnixEpoch);

        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            router.HandleKey(key, HotkeyModifiers.None, DictationPhase.Idle));
        Assert.Empty(plan.HotkeyActionIds);
    }
}
