#!/usr/bin/env python3
"""Project-specific localization checks.

This complements BartyCrouch:
- BartyCrouch validates .strings syntax and basic consistency.
- This script verifies table/language key parity across resource roots and
  catches high-confidence generated placeholder copy in visible UI namespaces.
"""

from __future__ import annotations

import re
import sys
import ast
from dataclasses import dataclass
from pathlib import Path


RESOURCE_ROOTS = [
    Path("Sources/VoxFlowApp/Resources"),
    Path("Sources/VoxFlowScreenshotKit/Resources"),
]

SWIFT_SOURCE_ROOTS = [
    Path("Sources"),
]

EXPECTED_LANGUAGES = {"en", "zh-Hans", "zh-Hant", "ja", "ko"}

UNSAFE_LOCALIZED_FORMAT_BASELINE = 0

UNSAFE_LOCALIZED_FORMAT = re.compile(r"String\s*\(\s*format\s*:\s*L10n\.localize\s*\(", re.MULTILINE)

VISIBLE_QUALITY_PREFIXES = (
    "home.",
    "installed_app_selector.",
    "navigation.route.",
    "chat.",
    "correction.",
    "help.",
    "model.llm_provider.",
    "recording.hud.",
    "recording.result.",
    "recording.feedback.",
    "settings.appearance.",
    "settings.audio.",
    "settings.audio_input.",
    "settings.data.",
    "settings.interface_language.",
    "settings.message.",
    "settings.output.",
    "settings.permissions.",
    "settings.privacy.",
    "settings.shortcuts.",
    "settings.system.",
    "settings.task.",
    "settings.window.",
    "settings.workflow_name.",
    "settings.task.dictation.section.",
    "settings.task.input_",
    "settings.task.recognition_language.",
    "smart.config.",
    "screenshot.record.",
    "screenshot.result.",
    "style.profile.",
    "style.view.",
    "style.action.",
    "style.app_routing.",
    "style.feedback.",
    "subtitle.editor.",
    "subtitle.status.",
    "vibe.",
)

PLACEHOLDER_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"\bview title\b",
        r"\bConfigure [a-z]+(?: [a-z]+)+\\.?\b",
        r"\b(?:page|panel|input|alias|target|details|filter|status|header|task|workflow|configuration|editor|privacy|permissions|shortcuts|links|overlay) (?:title|subtitle|placeholder|help|status|action|button|field|empty|cancel|confirm|save|delete|copy|open|close|failed|saved)\\b",
        r"\btask input\b",
        r"\btask recognition\b",
        r"\btask dictation\b",
        r"\bprofile .+ category\b",
        r"\bconfigure profile\b",
        r"\bprompt editor\b",
        r"\bAI\s+编程\s+时间\b",
        r"\bAI\s+编程\s+(?:当前|最近|分页|别名|助手)\b",
        r"\bcurrent agents\b",
        r"\brecent dispatches\b",
        r"\bpage title\b",
        r"\bRecord stats\b",
        r"\bRecord (?:details|copy|deleted|opened|No|filter|search|Next|Prev)\b",
        r"\bRecording Hud\b",
        r"\bSettings (?:Task|Window|Workflow|Shortcuts|Message|Output)\b",
        r"\bHelp Cards\b",
        r"\bLLM provider (?:add|delete|empty|field|model|save|test|toggle|required|current)\b",
        r"\bModel LLM Provider\b",
        r"\brecord详情\b",
        r"\brecord(?:已|大小|筛选|详情|原始|压制)\b",
        r"\b帮助\s+(?:cards|links|overlay|分页|权限|区域|qr)\b",
        r"\b设置\s+(?:窗口|任务|权限|隐私|消息|音频|数据|外观)\b",
        r"\b(?:配置|設置|設定)\s*(?:外观|外觀|音频|音訊|音声|数据|資料|データ).*(?:标题|標題|タイトル|字幕|占位|帮助|幫助|ヘルプ|enable|toggle|device|folder|reset)\b",
        r"\b模型\s+llm\s+服务\b",
        r"\b截图\s+媒体\b",
        r"\b录屏\s+hud\b",
        r"\b字幕\s+(?:editor|错误|状态)\b",
        r"\b风格\s+(?:操作|routing|错误)\b",
        r"风格\s+配置\s+.+\s+字幕",
        r"风格\s+视图\s+标题",
        r"スタイル\s+.*字幕",
        r"スクリーンショット\s+メディア",
        r"録画\s+hud",
        r"스타일\s+.*자막",
        r"스크린샷\s+미디어",
        r"녹화\s+hud",
    ]
]

ALLOWED_FOREIGN_TOKENS = {
    "AI",
    "ASR",
    "API",
    "Apple",
    "AssemblyAI",
    "Agent",
    "Bundle",
    "Caps",
    "CapsLock",
    "CLI",
    "Codex",
    "Command",
    "Control",
    "Dock",
    "GitHub",
    "HTTP",
    "HTTPS",
    "JSON",
    "LLM",
    "Lock",
    "Mac",
    "MCP",
    "OCR",
    "OpenAI",
    "Option",
    "PNG",
    "Shell",
    "Shift",
    "UTF-8",
    "URL",
    "VoxFlow",
    "Finder",
    "FunASR",
    "Groq",
    "Mistral",
    "Nemotron",
    "NVIDIA",
    "Omnilingual",
    "Paraformer",
    "Parakeet",
    "Qwen3",
    "Scribe",
    "SenseVoice",
    "Voxtral",
    "Whisper",
    "ElevenLabs",
    "vox",
    "macOS",
}

CHINESE_LOCALES = {"zh-Hans", "zh-Hant"}

ALLOWED_ASCII_VISIBLE_VALUES_IN_CHINESE = {
    "Agent CLI",
    "Claude Code",
    "CodeBuddy",
    "Codex",
    "LLM",
    "VoxFlow",
}

ASCII_DATE_FORMAT = re.compile(r"[yMdHhmsaSAZz:/.,\s%-]+")

STRINGS_LINE = re.compile(
    r'^\s*(?:"((?:[^"\\]|\\.)*)"|([A-Za-z_][A-Za-z0-9_]*))\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$'
)


@dataclass(frozen=True)
class StringsEntry:
    key: str
    value: str
    line: int


def unescape_strings_literal(value: str) -> str:
    try:
        return ast.literal_eval(f'"{value}"')
    except (SyntaxError, ValueError):
        return value


def parse_strings_file(path: Path) -> tuple[dict[str, StringsEntry], list[str]]:
    entries: dict[str, StringsEntry] = {}
    errors: list[str] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*") or stripped.endswith("*/"):
            continue
        match = STRINGS_LINE.match(line)
        if not match:
            errors.append(f"{path}:{line_number}: invalid .strings line")
            continue
        key = unescape_strings_literal(match.group(1) or match.group(2))
        value = unescape_strings_literal(match.group(3))
        if key in entries:
            previous = entries[key].line
            errors.append(f"{path}:{line_number}: duplicate key '{key}' (first seen on line {previous})")
            continue
        entries[key] = StringsEntry(key=key, value=value, line=line_number)
    return entries, errors


def strings_tables(root: Path) -> dict[str, dict[str, Path]]:
    tables: dict[str, dict[str, Path]] = {}
    for path in sorted(root.glob("*.lproj/*.strings")):
        language = path.parent.name.removesuffix(".lproj")
        tables.setdefault(path.name, {})[language] = path
    return tables


def visible_quality_key(key: str) -> bool:
    return key.startswith(VISIBLE_QUALITY_PREFIXES)


def contains_cjk_or_kana_or_hangul(value: str) -> bool:
    return bool(re.search(r"[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]", value))


def foreign_tokens(value: str) -> list[str]:
    tokens = re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", value)
    return [token for token in tokens if token not in ALLOWED_FOREIGN_TOKENS and not token.startswith("%")]


def untranslated_ascii_visible_value(language: str, value: str) -> bool:
    if language not in CHINESE_LOCALES:
        return False
    if not re.search(r"[A-Za-z]", value):
        return False
    if contains_cjk_or_kana_or_hangul(value):
        return False
    if value in ALLOWED_ASCII_VISIBLE_VALUES_IN_CHINESE:
        return False
    if ASCII_DATE_FORMAT.fullmatch(value):
        return False
    return True


def quality_errors(language: str, path: Path, entries: dict[str, StringsEntry]) -> list[str]:
    errors: list[str] = []
    for entry in entries.values():
        if not visible_quality_key(entry.key):
            continue
        value = entry.value.strip()
        if not value:
            errors.append(f"{path}:{entry.line}: empty value for '{entry.key}'")
            continue
        if value == entry.key:
            errors.append(f"{path}:{entry.line}: value for '{entry.key}' falls back to its key")
        for pattern in PLACEHOLDER_PATTERNS:
            if pattern.search(value):
                errors.append(
                    f"{path}:{entry.line}: suspicious generated copy for '{entry.key}': {entry.value!r}"
                )
                break
        if untranslated_ascii_visible_value(language, value):
            errors.append(
                f"{path}:{entry.line}: untranslated ASCII copy in Chinese locale for "
                f"'{entry.key}': {entry.value!r}"
            )
        if language != "en" and contains_cjk_or_kana_or_hangul(value):
            tokens = foreign_tokens(value)
            if tokens:
                errors.append(
                    f"{path}:{entry.line}: mixed untranslated token(s) {tokens} in '{entry.key}': {entry.value!r}"
                )
    return errors


def check_root(root: Path) -> list[str]:
    errors: list[str] = []
    tables = strings_tables(root)
    if not tables:
        return [f"{root}: no .strings tables found"]

    for table_name, language_paths in sorted(tables.items()):
        languages = set(language_paths)
        if languages != EXPECTED_LANGUAGES:
            missing = sorted(EXPECTED_LANGUAGES - languages)
            extra = sorted(languages - EXPECTED_LANGUAGES)
            if missing:
                errors.append(f"{root}/{table_name}: missing language file(s): {', '.join(missing)}")
            if extra:
                errors.append(f"{root}/{table_name}: unexpected language file(s): {', '.join(extra)}")

        parsed: dict[str, dict[str, StringsEntry]] = {}
        for language, path in sorted(language_paths.items()):
            entries, parse_errors = parse_strings_file(path)
            errors.extend(parse_errors)
            parsed[language] = entries
            errors.extend(quality_errors(language, path, entries))

        if not parsed:
            continue

        all_keys = set().union(*(entries.keys() for entries in parsed.values()))
        for language, entries in sorted(parsed.items()):
            missing = sorted(all_keys - set(entries))
            extra = sorted(set(entries) - (all_keys - set(entries)))
            if missing:
                preview = ", ".join(missing[:20])
                suffix = "" if len(missing) <= 20 else f" ... (+{len(missing) - 20} more)"
                errors.append(f"{language_paths[language]}: missing {len(missing)} key(s): {preview}{suffix}")
            # `extra` is intentionally not reported: all_keys is the union, so keys
            # are "extra" only relative to another language and will be reported as
            # missing there.
            _ = extra

    return errors


def unsafe_localized_format_violations() -> list[str]:
    violations: list[str] = []
    for root in SWIFT_SOURCE_ROOTS:
        for path in sorted(root.rglob("*.swift")):
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if UNSAFE_LOCALIZED_FORMAT.search(line):
                    violations.append(f"{path}:{line_number}: {line.strip()}")
    return violations


def main() -> int:
    errors: list[str] = []
    for root in RESOURCE_ROOTS:
        errors.extend(check_root(root))

    unsafe_format_violations = unsafe_localized_format_violations()
    if len(unsafe_format_violations) > UNSAFE_LOCALIZED_FORMAT_BASELINE:
        added = len(unsafe_format_violations) - UNSAFE_LOCALIZED_FORMAT_BASELINE
        errors.append(
            "Unsafe localized String(format:) usage increased by "
            f"{added}; prefer generated SwiftGen typed localization helpers."
        )
        errors.extend(unsafe_format_violations[-added:])

    if errors:
        print("Localization check failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(
        "Localization check passed: key parity, duplicates, empty values, visible-copy heuristics, "
        "and unsafe localized format baseline are clean."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
