namespace VoxFlow.Windows.Infrastructure.Runtime;

public static class InstallerLayoutContract
{
    public const string ApplicationExecutable = "VoxFlow.Windows.App.exe";
    public const string NativeQwenBridge = "qwen_asr.dll";
    public const string ProjectLicense = "LICENSE";
    public const string ThirdPartyNotices = "THIRD-PARTY-NOTICES.md";

    public static IReadOnlyList<string> RequiredRelativePaths { get; } =
    [
        ApplicationExecutable,
        NativeQwenBridge,
        ProjectLicense,
        ThirdPartyNotices,
    ];
}
