namespace VoxFlow.Windows.Infrastructure.Runtime;

public static class InstallerLayoutContract
{
    public const string ApplicationExecutable = "VoxFlow.exe";
    public const string NativeQwenBridge = "qwen_asr.dll";
    public const string NativeQwenManifest = @"Qwen\QWEN_NATIVE_RUNTIME_MANIFEST.json";
    public const string QwenModelProvenance = @"Qwen\MODEL_PROVENANCE.json";
    public const string QwenReadinessCanary = @"Qwen\readiness-canary.wav";
    public const string FfmpegManifest = @"runtime\ffmpeg\FFMPEG_RUNTIME_MANIFEST.json";
    public const string FfmpegExecutable = @"runtime\ffmpeg\ffmpeg.exe";
    public const string FfprobeExecutable = @"runtime\ffmpeg\ffprobe.exe";
    public const string FfmpegNotices = @"runtime\ffmpeg\THIRD_PARTY_NOTICES.md";
    public const string BuiltinAgentManifest = @"runtime\agent\VOXFLOW_AGENT_RUNTIME_MANIFEST.json";
    public const string BuiltinAgentExecutable = @"runtime\agent\voxflow-agent.exe";
    public const string OcrManifest = @"runtime\ocr\TESSERACT_RUNTIME_MANIFEST.json";
    public const string OcrExecutable = @"runtime\ocr\tesseract.exe";
    public const string OcrLicense = @"runtime\ocr\LICENSE.txt";
    public const string OcrEnglishModel = @"runtime\ocr\tessdata\eng.traineddata";
    public const string ProjectLicense = @"licenses\LICENSE-GPL-3.0-or-later.txt";
    public const string ThirdPartyNotices = @"licenses\THIRD-PARTY-NOTICES.md";

    public static IReadOnlyList<string> RequiredRelativePaths { get; } =
    [
        ApplicationExecutable,
        NativeQwenBridge,
        NativeQwenManifest,
        QwenModelProvenance,
        QwenReadinessCanary,
        FfmpegManifest,
        FfmpegExecutable,
        FfprobeExecutable,
        FfmpegNotices,
        BuiltinAgentManifest,
        BuiltinAgentExecutable,
        OcrManifest,
        OcrExecutable,
        OcrLicense,
        OcrEnglishModel,
        ProjectLicense,
        ThirdPartyNotices,
    ];
}
