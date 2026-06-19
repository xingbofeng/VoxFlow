#!/usr/bin/env python3
"""Repository architecture guard for the VoxFlow SwiftPM migration.

The checker is intentionally usable before the full multi-target migration is
complete: it enforces rules only for target directories that already exist, and
it validates package dependency cycles for every declared target.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


TARGET_PATTERN = re.compile(
    r"\.(?:target|executableTarget|testTarget)\s*\(\s*name:\s*\"([^\"]+)\"(?P<body>.*?)\n\s*\)",
    re.DOTALL,
)
DEPENDENCIES_PATTERN = re.compile(r"dependencies:\s*\[(?P<body>.*?)\]", re.DOTALL)
STRING_PATTERN = re.compile(r"\"([^\"]+)\"")
IMPORT_PATTERN = re.compile(r"^\s*import\s+([A-Za-z0-9_]+)\b", re.MULTILINE)
CJK_PATTERN = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]")
PROVIDER_DATABASE_TOKENS = (
    "DatabaseQueue",
    "SQLiteConnection",
    "SQLiteStatement",
    "SQLiteError",
    "sqlite3_",
)
LEGACY_VOICEINPUT_TOKENS = (
    "VoiceInput",
    "com.voiceinput.app",
    "VoiceInput_SelectedLanguage",
    "com.xingbofeng.VoiceInput",
    "Application Support/VoiceInput",
    "voiceinput.sqlite",
)
LEGACY_VOICEINPUT_ALLOWED_PATHS = {
    Path("Sources/VoxFlowDomain/Branding/ProductBrand.swift"),
}
UI_TARGETS = {
    "VoxFlowFeatures",
    "VoxFlowDesignSystem",
}
MODEL_PATH_TOKENS = (
    "ModelStorePaths",
    "modelsDirectory",
    "modelDirectory",
    "modelPath",
    "modelURL",
    "modelRootURL",
)
APP_DELEGATE_MODEL_AVAILABILITY_TOKENS = (
    "modelsExist(",
    "isQwen3ModelAvailableOnDisk",
    "Qwen3ModelManifest",
    "SherpaASRModelVariant",
    "WhisperKitModelVariant",
    "SenseVoiceModels",
    "ParaformerModels",
)
APP_DELEGATE_MODEL_DOWNLOAD_TOKENS = (
    "Qwen3ModelDownloader",
    "SherpaASRModelDownloader",
    "downloadModel(",
    "downloadQwen3Model",
    "downloadLocalModel",
)
APP_DELEGATE_RECORDING_PERMISSION_TOKENS = (
    "AudioRecorder.checkPermission",
    "AudioRecorder.requestPermission",
    "SpeechRecognizer.checkPermission",
    "SpeechRecognizer.requestPermission",
    "RecordingPermissionPolicy.hasRequiredPermissions",
)
APP_DELEGATE_ASR_STATE_TOKENS = (
    "ASRManager()",
    "ASRMenuStateResolver",
)
APP_DELEGATE_MENU_BAR_TOKENS = (
    "NSMenuDelegate",
    "languageMenuItems",
    "asrEngineMenuItems",
    "refiningMenuItem",
    "setupASREngineMenu",
    "updateASREngineMenuState",
    "updateLanguageMenuState",
)
APP_DELEGATE_HUD_UPDATE_TOKENS = (
    "overlayController.show(",
    "overlayController.showWithoutReset(",
    "overlayController.dismiss(",
    "overlayController.updateTranscription(",
    "overlayController.updateAgentComposeStatus(",
    "overlayController.updateStreamingText(",
    "overlayController.updateRMS(",
    "overlayController.showTemporaryMessage(",
)
APP_DELEGATE_TEXT_INPUT_TOKENS = (
    "textInjector.inject(",
    "PasteboardSnapshot",
    "PasteboardTransaction",
    "PasteCompletionWaiter",
    "CGEvent(keyboardEventSource:",
)
APP_RUNTIME_PREWARM_TOKENS = (
    "ASRModelPrewarmCenter",
    "ASRModelPrewarming",
    "ASREngineWarmupProviding",
    "ASRConfigurationEngineFactory",
    "prewarmCurrentASREngine",
    "prewarmSelectedEngine",
    "prewarmSelectedEngineIfAvailable",
    "cancelPrewarming(",
    "waitUntilReadyForAudio(",
    "modelPrewarmer",
)
DICTATION_ORCHESTRATOR_DIRECT_OUTPUT_TOKENS = (
    "textInjector.inject(",
    "clipboardService.setString(",
)
VOICE_INPUT_APP_CLIPBOARD_IMPLEMENTATION_TOKENS = (
    "struct PasteboardSnapshot",
    "struct PasteboardTransaction",
    "struct PasteCompletionWaiter",
    "enum PasteCompletionWaitResult",
)
VOICE_INPUT_APP_TEXT_INSERTION_CONTRACT_TOKENS = (
    "enum InjectionResult",
    "protocol TextInjecting",
)
VOICE_INPUT_APP_FAST_PASTE_IMPLEMENTATION_TOKENS = (
    "final class TextInjector",
    "CGEvent(keyboardEventSource:",
    "TISCopyCurrentKeyboardInputSource",
    "TISSelectInputSource",
)
VOICE_INPUT_APP_QWEN_RUNTIME_IMPLEMENTATION_TOKENS = (
    "Qwen3StreamingState",
    "Qwen3StreamingRuntimeDriver(",
    "makeSession(",
    ".addAudio(",
)
VOICE_INPUT_APP_QWEN_PROVIDER_CONSTRUCTION_TOKENS = (
    "Qwen3ModelManifest.supportedModelExists",
    "Qwen3ASRProvider(",
    "Qwen3ProviderDescriptor.descriptor(",
)
VOICE_INPUT_APP_QWEN_READINESS_IMPLEMENTATION_TOKENS = (
    "ModelPrewarmCanaryRunner",
    "Qwen3ModelRuntimePreparer(",
    "Qwen3ModelCanaryAudio",
    "Qwen3ModelStoreMetadata.metadata",
)
VOICE_INPUT_APP_QWEN_DIRECT_DOWNLOAD_IMPLEMENTATION_TOKENS = (
    "URLSessionDownloadDelegate",
    "URLSession(",
    "downloadTask(",
    "didWriteData",
    "didFinishDownloadingTo",
)
QWEN_STREAMING_DRIVER_PREWARM_TOKENS = (
    "session?.prewarm(",
    "session.prewarm(",
    ".prewarm()",
)
VOICE_INPUT_APP_WHISPER_RUNTIME_IMPLEMENTATION_TOKENS = (
    "import WhisperKit",
    "WhisperKit(",
    "WhisperKitConfig(",
    "LocalWhisperKitTranscriber",
    "WhisperKitBatchASREngine",
)
VOICE_INPUT_APP_SENSEVOICE_RUNTIME_IMPLEMENTATION_TOKENS = (
    "SenseVoiceModels.load(",
    "SenseVoiceModels.download(",
    "SenseVoiceManager(",
    "SenseVoiceManagerTranscriber",
)
VOICE_INPUT_APP_PARAFORMER_IMPLEMENTATION_TOKENS = (
    "ParaformerModels",
    "ParaformerManager",
    "VOX_SHERPA_PARAFORMER",
    ".paraformerChinese",
    ".paraformerEnglish",
    "ParaformerLanguage",
    "ASRParaformer",
)
ASR_MANAGER_DIRECT_QWEN_LEGACY_ENGINE_TOKENS = (
    "Qwen3ASREngine(",
)
ASR_MANAGER_DIRECT_FUNASR_LEGACY_ENGINE_PATTERN = re.compile(
    r"case\s+\.funASR\s*:\s*return\s+SherpaBatchASREngine\s*\(",
    re.DOTALL,
)
ASR_MANAGER_DIRECT_SENSEVOICE_LEGACY_ENGINE_PATTERN = re.compile(
    r"case\s+\.senseVoice\s*:\s*return\s+FluidAudioBatchASREngine\s*\(",
    re.DOTALL,
)
VIEW_MODEL_CONCRETE_ENVIRONMENT_TOKENS = (
    "private let environment: AppEnvironment",
    "var environment: AppEnvironment",
    "init(environment: AppEnvironment",
)
SETTINGS_WINDOW_DIRECT_MODEL_DOWNLOAD_TOKENS = (
    "Qwen3ModelDownloader()",
)
SETTINGS_WINDOW_DIRECT_QWEN_MANIFEST_TOKENS = (
    "Qwen3ModelManifest.manifest(",
)
ASR_PROVIDER_VIEW_MODEL_DIRECT_QWEN_MANIFEST_TOKENS = (
    "Qwen3ModelManifest.manifest(",
)
ASR_PROVIDER_VIEW_MODEL_DIRECT_QWEN_DOWNLOADER_TOKENS = (
    "Qwen3ModelDownloader()",
)
MAIN_ACTOR_TASK_PATTERN = re.compile(
    r"Task\s*\{\s*@MainActor[^\n]*\n(?P<body>.*?)\n\s*\}",
    re.DOTALL,
)


@dataclass(frozen=True)
class Target:
    name: str
    dependencies: tuple[str, ...]


def parse_package(package_path: Path) -> dict[str, Target]:
    contents = package_path.read_text(encoding="utf-8")
    targets: dict[str, Target] = {}
    for match in TARGET_PATTERN.finditer(contents):
        name = match.group(1)
        body = match.group("body")
        dependencies: list[str] = []
        if dependency_match := DEPENDENCIES_PATTERN.search(body):
            dependencies = STRING_PATTERN.findall(dependency_match.group("body"))
        targets[name] = Target(name=name, dependencies=tuple(dependencies))
    return targets


def detect_cycles(targets: dict[str, Target]) -> list[str]:
    visiting: set[str] = set()
    visited: set[str] = set()
    stack: list[str] = []
    violations: list[str] = []

    def visit(name: str) -> None:
        if name in visited:
            return
        if name in visiting:
            start = stack.index(name)
            violations.append("Package target dependency cycle: " + " -> ".join(stack[start:] + [name]))
            return

        visiting.add(name)
        stack.append(name)
        for dependency in targets.get(name, Target(name, ())).dependencies:
            if dependency in targets:
                visit(dependency)
        stack.pop()
        visiting.remove(name)
        visited.add(name)

    for target_name in sorted(targets):
        visit(target_name)
    return violations


def swift_files(directory: Path) -> list[Path]:
    if not directory.exists():
        return []
    return sorted(path for path in directory.rglob("*.swift") if path.is_file())


def imported_modules(path: Path) -> set[str]:
    return set(IMPORT_PATTERN.findall(path.read_text(encoding="utf-8")))


def string_literals(contents: str) -> list[str]:
    return [match.group(1) for match in STRING_PATTERN.finditer(contents)]


def has_user_visible_literal(contents: str) -> bool:
    return any(CJK_PATTERN.search(value) for value in string_literals(contents))


def relative(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def source_boundary_violations(source_root: Path, targets: dict[str, Target]) -> list[str]:
    violations: list[str] = []

    for target_name in sorted(targets):
        target_dir = source_root / target_name
        files = swift_files(target_dir)

        for path in files:
            contents = path.read_text(encoding="utf-8")
            imports = set(IMPORT_PATTERN.findall(contents))
            display_path = relative(path, source_root.parent)

            if target_name.startswith("VoxFlowProvider") and "SwiftUI" in imports:
                violations.append(f"{display_path}: Provider target must not import SwiftUI")

            if target_name.startswith("VoxFlowProvider"):
                if any(token in contents for token in PROVIDER_DATABASE_TOKENS):
                    violations.append(f"{display_path}: Provider target must not access database primitives")

                provider_imports = sorted(
                    module
                    for module in imports
                    if module.startswith("VoxFlowProvider") and module != target_name
                )
                for module in provider_imports:
                    violations.append(
                        f"{display_path}: Provider target must not import provider target {module}"
                    )

            if (
                target_name.startswith("VoxFlow")
                and Path(display_path) not in LEGACY_VOICEINPUT_ALLOWED_PATHS
                and any(
                token in contents for token in LEGACY_VOICEINPUT_TOKENS
                )
            ):
                violations.append(
                    f"{display_path}: Source target must not reference legacy VoiceInput brand or storage identifiers"
                )

            if target_name == "VoxFlowAudio" and ("SwiftUI" in imports or "AppKit" in imports):
                violations.append(f"{display_path}: Audio target must not import UI frameworks")

            if target_name == "VoxFlowAudio" and "UserDefaults" in contents:
                violations.append(f"{display_path}: Audio target must not access UserDefaults")

            if target_name == "VoxFlowModelStore" and ("SwiftUI" in imports or "AppKit" in imports):
                violations.append(f"{display_path}: ModelStore target must not import UI frameworks")

            if target_name == "VoxFlowTextInsertion":
                provider_imports = sorted(module for module in imports if module.startswith("VoxFlowProvider"))
                for module in provider_imports:
                    violations.append(
                        f"{display_path}: TextInsertion target must not import provider target {module}"
                    )

            if target_name == "VoxFlowLocalization":
                feature_imports = sorted(module for module in imports if module == "VoxFlowFeatures")
                for module in feature_imports:
                    violations.append(
                        f"{display_path}: Localization target must not import Feature target {module}"
                    )

            if target_name in UI_TARGETS and any(token in contents for token in MODEL_PATH_TOKENS):
                violations.append(f"{display_path}: UI target must not access model store paths directly")

            if target_name in UI_TARGETS and has_user_visible_literal(contents):
                violations.append(f"{display_path}: UI target must not hardcode user-visible strings")

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_MODEL_AVAILABILITY_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must not perform direct model availability checks"
                )

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_MODEL_DOWNLOAD_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must not perform direct model downloads"
                )

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_RECORDING_PERMISSION_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must use RecordingPermissionService for recording permissions"
                )

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_ASR_STATE_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must use ASRCoordinator for ASR state"
                )

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_MENU_BAR_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must use MenuBarCoordinator for status menu state"
                )

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_HUD_UPDATE_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must use VoiceHUDFeatureController for HUD updates"
                )

            if path.name == "AppDelegate.swift" and any(
                token in contents for token in APP_DELEGATE_TEXT_INPUT_TOKENS
            ):
                violations.append(
                    f"{display_path}: AppDelegate must not perform direct text input or clipboard insertion"
                )

            if target_name == "VoxFlowApp" and any(
                token in contents for token in APP_RUNTIME_PREWARM_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not prewarm ASR runtime during app launch, model switch, or dictation start"
                )

            if path.name in {"AppDelegate.swift", "NotesRecordingService.swift"} and any(
                "appendAudioBuffer(" in match.group("body")
                for match in MAIN_ACTOR_TASK_PATTERN.finditer(contents)
            ):
                violations.append(
                    f"{display_path}: Audio recorder delegate must not hop to MainActor to append audio buffers"
                )

            if path.name == "ASREngine.swift" and (
                "AVAudioPCMBuffer" in contents or "appendAudioBuffer(" in contents
            ):
                violations.append(
                    f"{display_path}: ASREngine must accept AudioFrame instead of raw AVAudioPCMBuffer"
                )

            if path.name == "DictationOrchestrator.swift" and any(
                token in contents for token in DICTATION_ORCHESTRATOR_DIRECT_OUTPUT_TOKENS
            ):
                violations.append(
                    f"{display_path}: DictationOrchestrator must deliver text through OutputService"
                )

            if target_name == "VoxFlowApp" and path.name == "TextInjector.swift" and any(
                token in contents for token in VOICE_INPUT_APP_CLIPBOARD_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not own clipboard transaction implementation"
                )

            if target_name == "VoxFlowApp" and any(
                token in contents for token in VOICE_INPUT_APP_TEXT_INSERTION_CONTRACT_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not own text insertion contract"
                )

            if target_name == "VoxFlowApp" and any(
                token in contents for token in VOICE_INPUT_APP_FAST_PASTE_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not own fast paste text insertion implementation"
                )

            if target_name == "VoxFlowApp" and path.name == "Qwen3ASREngine.swift" and any(
                token in contents for token in VOICE_INPUT_APP_QWEN_RUNTIME_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp Qwen legacy adapter must not own streaming runtime implementation"
                )

            if target_name == "VoxFlowApp" and path.name == "Qwen3ASREngine.swift" and any(
                token in contents for token in VOICE_INPUT_APP_QWEN_PROVIDER_CONSTRUCTION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp Qwen legacy adapter must delegate provider construction to VoxFlowProviderQwen3"
                )

            if target_name == "VoxFlowApp" and path.name == "Qwen3ModelReadinessPreparer.swift" and any(
                token in contents for token in VOICE_INPUT_APP_QWEN_READINESS_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp Qwen readiness adapter must delegate prewarm and canary to VoxFlowProviderQwen3"
                )

            if target_name == "VoxFlowApp" and path.name == "Qwen3ModelDownloader.swift" and any(
                token in contents for token in VOICE_INPUT_APP_QWEN_DIRECT_DOWNLOAD_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp Qwen downloader adapter must delegate download implementation to VoxFlowProviderQwen3 ModelStore"
                )

            if target_name == "VoxFlowProviderQwen3" and path.name == "Qwen3StreamingRuntimeDriver.swift" and any(
                token in contents for token in QWEN_STREAMING_DRIVER_PREWARM_TOKENS
            ):
                violations.append(
                    f"{display_path}: Qwen3 streaming driver start must not prewarm runtime without audio"
                )

            if target_name == "VoxFlowApp" and any(
                token in contents for token in VOICE_INPUT_APP_WHISPER_RUNTIME_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not own Whisper runtime implementation"
                )

            if target_name == "VoxFlowApp" and any(
                token in contents for token in VOICE_INPUT_APP_SENSEVOICE_RUNTIME_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not own SenseVoice runtime implementation"
                )

            if target_name == "VoxFlowApp" and any(
                token in contents for token in VOICE_INPUT_APP_PARAFORMER_IMPLEMENTATION_TOKENS
            ):
                violations.append(
                    f"{display_path}: VoxFlowApp must not own Paraformer runtime, download, or selection implementation"
                )

            if target_name == "VoxFlowApp" and path.name == "ASRManager.swift" and any(
                token in contents for token in ASR_MANAGER_DIRECT_QWEN_LEGACY_ENGINE_TOKENS
            ):
                violations.append(
                    f"{display_path}: ASRManager must build Qwen through provider-backed adapter"
                )

            if (
                target_name == "VoxFlowApp"
                and path.name == "ASRManager.swift"
                and ASR_MANAGER_DIRECT_FUNASR_LEGACY_ENGINE_PATTERN.search(contents)
            ):
                violations.append(
                    f"{display_path}: ASRManager must build FunASR through provider-backed adapter"
                )

            if (
                target_name == "VoxFlowApp"
                and path.name == "ASRManager.swift"
                and ASR_MANAGER_DIRECT_SENSEVOICE_LEGACY_ENGINE_PATTERN.search(contents)
            ):
                violations.append(
                    f"{display_path}: ASRManager must build SenseVoice through provider-backed adapter"
                )

            if path.name.endswith("ViewModel.swift") and any(
                token in contents for token in VIEW_MODEL_CONCRETE_ENVIRONMENT_TOKENS
            ):
                violations.append(
                    f"{display_path}: ViewModel must depend on AppServiceProviding instead of concrete AppEnvironment"
                )

            if path.name == "SettingsWindowController.swift" and any(
                token in contents for token in SETTINGS_WINDOW_DIRECT_MODEL_DOWNLOAD_TOKENS
            ):
                violations.append(
                    f"{display_path}: SettingsWindowController must receive model download dependencies instead of constructing them"
                )

            if path.name == "SettingsWindowController.swift" and any(
                token in contents for token in SETTINGS_WINDOW_DIRECT_QWEN_MANIFEST_TOKENS
            ):
                violations.append(
                    f"{display_path}: SettingsWindowController must delegate Qwen manifest creation to model download dependencies"
                )

            if path.name == "ASRProviderViewModel.swift" and any(
                token in contents for token in ASR_PROVIDER_VIEW_MODEL_DIRECT_QWEN_MANIFEST_TOKENS
            ):
                violations.append(
                    f"{display_path}: ASRProviderViewModel must delegate Qwen manifest creation to model download dependencies"
                )

            if path.name == "ASRProviderViewModel.swift" and any(
                token in contents for token in ASR_PROVIDER_VIEW_MODEL_DIRECT_QWEN_DOWNLOADER_TOKENS
            ):
                violations.append(
                    f"{display_path}: ASRProviderViewModel must receive Qwen model download dependencies from Qwen3ModelDownloader.live()"
                )

    return violations


def run(package_path: Path, source_root: Path) -> list[str]:
    violations: list[str] = []
    if not package_path.exists():
        return [f"{package_path}: Package.swift not found"]
    if not source_root.exists():
        return [f"{source_root}: source root not found"]

    targets = parse_package(package_path)
    if not targets:
        violations.append(f"{package_path}: no SwiftPM targets found")
        return violations

    violations.extend(detect_cycles(targets))
    violations.extend(source_boundary_violations(source_root, targets))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate VoxFlow SwiftPM architecture boundaries.")
    parser.add_argument("--package", type=Path, default=Path("Package.swift"))
    parser.add_argument("--source-root", type=Path, default=Path("Sources"))
    args = parser.parse_args()

    violations = run(args.package, args.source_root)
    if violations:
        print("architecture-check failed:")
        for violation in violations:
            print(f"- {violation}")
        return 1

    print("architecture-check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
