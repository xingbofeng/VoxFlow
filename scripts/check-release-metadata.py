#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import plistlib
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

from release_platforms import ASSET_KINDS, PlatformContractError, validate_release_assets


ROOT = Path(__file__).resolve().parents[1]
PLIST = ROOT / "Sources/VoxFlowApp/Resources/Info.plist"
IOS_PROJECT = ROOT / "Apps/VoxFlowiOS/project.yml"
IOS_INFO_PLISTS = [
    ROOT / "Apps/VoxFlowiOS/VoxFlowiOS/Info.plist",
    ROOT / "Apps/VoxFlowiOS/Keyboard/Info.plist",
]
WINDOWS_PROJECT = ROOT / "VoxFlow.Windows/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
README_PATHS = ["README.md", "README.zh-CN.md", "README.zh-TW.md", "README.ja.md", "README.ko.md"]
IOS_IPA_REFERENCE_RE = re.compile(r"Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa")
RELEASE_NOTE_METADATA_HEADING_RE = re.compile(r"^## 发布元数据[ \t]*$", re.MULTILINE)
RELEASE_NOTE_SECTION_HEADING_RE = re.compile(r"^##\s+", re.MULTILINE)
RELEASE_NOTE_IOS_ASSET_ROW_RE = re.compile(
    r"^- iOS Ad Hoc IPA：`Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa`[ \t]*$",
    re.MULTILINE,
)
RELEASE_NOTE_VERSION_ROW_RE = re.compile(
    r"^- `CFBundleShortVersionString`：[^\n]*$",
    re.MULTILINE,
)
RELEASE_NOTE_BUILD_ROW_RE = re.compile(
    r"^- `CFBundleVersion`：[^\n]*$",
    re.MULTILINE,
)
README_IOS_DOWNLOAD_ROW_RE = re.compile(
    r"^\| iOS 17\+ \| .*Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa.*\|[ \t]*$",
    re.MULTILINE,
)
README_IOS_DOWNLOAD_LINK_RE = re.compile(
    r"\[[^\]]+\]\(\s*(?:<)?[^)\s]*Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa[^)]*\)",
    re.IGNORECASE,
)
README_IOS_AUTOLINK_RE = re.compile(
    r"<https?://[^>\s]*Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa[^>\s]*>",
    re.IGNORECASE,
)
README_IOS_BARE_GITHUB_URL_RE = re.compile(
    r"https://github\.com/xingbofeng/VoxFlow/releases/download/"
    r"v[0-9]+\.[0-9]+\.[0-9]+/"
    r"Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa(?:[?#][^\s<]*)?",
    re.IGNORECASE,
)
README_REFERENCE_LINK_RE = re.compile(r"\[([^\]]+)\]\[([^\]]*)\]")
README_SHORTCUT_REFERENCE_LINK_RE = re.compile(
    r"(?<![!\[])\[([^\]\n]+)\](?![\[(:])"
)
README_REFERENCE_DEFINITION_RE = re.compile(
    r"^\s*\[([^\]]+)\]:\s*(?:<)?([^>\s]+)",
    re.MULTILINE,
)
README_REFERENCE_DEFINITION_LINE_RE = re.compile(r"^\s*\[[^\]]+\]:\s*(?:<)?[^>\s]+")
EMBEDDED_RELEASE_DATA_RE = re.compile(
    r'<script\b(?=[^>]*\bid=["\']voxflow-release-data["\'])[^>]*>.*?</script\s*>',
    re.IGNORECASE | re.DOTALL,
)
JAVASCRIPT_RUNTIME_PROBE = r"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(0, "utf8");
const sandbox = Object.create(null);
const runtimePrelude = String.raw`
globalThis.hrefs = [];
globalThis.readyHandlers = { DOMContentLoaded: [], load: [] };

function registerReadyHandler(name, callback) {
  if (Object.prototype.hasOwnProperty.call(globalThis.readyHandlers, name) && typeof callback === "function") {
    globalThis.readyHandlers[name].push(callback);
  }
}

function createElement() {
  const element = {
    dataset: {},
    classList: { add() {}, remove() {} },
    append() {},
    appendChild() {},
    removeAttribute() {},
    querySelector() { return createElement(); },
    querySelectorAll() { return []; },
    getAttribute() { return null; },
    setAttribute(name, value) {
      if (String(name).toLowerCase() === "href") globalThis.hrefs.push(String(value));
    },
    addEventListener() {},
    focus() {},
    contains() { return false; },
    closest() { return null; }
  };
  Object.defineProperty(element, "href", {
    get() { return ""; },
    set(value) { globalThis.hrefs.push(String(value)); }
  });
  return element;
}

class RuntimeURL {
  constructor(value, base = "") {
    const input = String(value);
    if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(input)) {
      this.value = input;
    } else if (input.startsWith("?")) {
      this.value = String(base).replace(/[?#].*$/, "") + input;
    } else {
      this.value = String(base).replace(/\/?$/, "/") + input.replace(/^\//, "");
    }
    this.hash = "";
  }

  toString() {
    return this.value;
  }
}

class RuntimeURLSearchParams {
  constructor(value = "") {
    this.values = new Map();
    if (typeof value === "string") {
      value.replace(/^\?/, "").split("&").filter(Boolean).forEach((entry) => {
        const [key, item = ""] = entry.split("=", 2);
        this.values.set(decodeURIComponent(key), decodeURIComponent(item));
      });
    } else if (value && typeof value === "object") {
      Object.entries(value).forEach(([key, item]) => this.values.set(key, String(item)));
    }
  }

  has(key) { return this.values.has(String(key)); }
  get(key) { return this.values.get(String(key)) || null; }
  set(key, value) { this.values.set(String(key), String(value)); }
  delete(key) { this.values.delete(String(key)); }
  toString() {
    return [...this.values.entries()]
      .map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value))
      .join("&");
  }
}

globalThis.document = {
  documentElement: {},
  head: createElement(),
  activeElement: null,
  title: "",
  querySelector() { return createElement(); },
  querySelectorAll() { return [createElement()]; },
  getElementById() { return createElement(); },
  createElement() { return createElement(); },
  addEventListener(name, callback) { registerReadyHandler(name, callback); },
  dispatchReadyHandlers() {
    ["DOMContentLoaded", "load"].forEach((name) => {
      globalThis.readyHandlers[name].forEach((callback) => callback({ type: name }));
    });
  }
};
globalThis.window = {
  location: { search: "", pathname: "/", hash: "", href: "https://example.invalid/" },
  navigator: { userAgent: "" },
  localStorage: { getItem() { return null; }, setItem() {} },
  addEventListener(name, callback) { registerReadyHandler(name, callback); }
};
globalThis.window.window = globalThis.window;
globalThis.history = { pushState() {}, replaceState() {} };
globalThis.IntersectionObserver = class { observe() {} unobserve() {} };
globalThis.URL = RuntimeURL;
globalThis.URLSearchParams = RuntimeURLSearchParams;
globalThis.console = { warn() {} };
globalThis.fetch = undefined;
`;
const options = { timeout: 1000, codeGeneration: { strings: false, wasm: false } };
vm.runInNewContext(runtimePrelude, sandbox, options);
const state = vm.runInNewContext(
  source + "\ndocument.dispatchReadyHandlers();\nJSON.stringify({ release, urls: releaseDownloadURLs, hrefs });",
  sandbox,
  options
);
process.stdout.write(state);
"""


def read_version() -> tuple[str, str]:
    with PLIST.open("rb") as handle:
        plist = plistlib.load(handle)
    return str(plist["CFBundleShortVersionString"]), str(plist["CFBundleVersion"])


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def read_windows_project_value(element: str) -> str | None:
    match = re.search(
        rf"<{element}>\s*([^<]+?)\s*</{element}>",
        read_text(WINDOWS_PROJECT),
    )
    return match.group(1).strip() if match is not None else None


def release_asset_names(version: str) -> dict[tuple[str, str], str]:
    return {
        ("macos", "dmg"): f"VoxFlow-{version}-macOS.dmg",
        ("windows", "installer"): f"VoxFlow-{version}-windows-x64-setup.exe",
        ("windows", "portable"): f"VoxFlow-{version}-windows-x64-portable.zip",
        ("ios", "ipa"): f"Mashangxie-{version}-iOS.ipa",
    }


def selected_assets(
    version: str,
    platforms: tuple[str, ...],
) -> list[tuple[str, str, str]]:
    names = release_asset_names(version)
    return [
        (platform, kind, names[(platform, kind)])
        for platform in platforms
        for kind in ASSET_KINDS[platform]
    ]


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def current_release_data(index: str) -> list[Any] | None:
    release_data_match = re.search(
        r'<script id="voxflow-release-data" type="application/json">\s*(.*?)\s*</script>',
        index,
        re.DOTALL,
    )
    if release_data_match is None:
        return None
    try:
        release_data = json.loads(release_data_match.group(1))
    except json.JSONDecodeError:
        return None
    return release_data if isinstance(release_data, list) else None


class ActivePageLinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str | None]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "a":
            return
        attributes = dict(attrs)
        platform = attributes.get("data-download-platform")
        if "href" in attributes or platform is not None:
            self.links.append((attributes.get("href") or "", platform))


def active_page_links(index: str) -> list[tuple[str, str | None]]:
    parser = ActivePageLinkParser()
    parser.feed(EMBEDDED_RELEASE_DATA_RE.sub("", index))
    parser.close()
    return parser.links


def markdown_without_code(text: str) -> str:
    result: list[str] = []
    fence_character: str | None = None
    fence_length = 0
    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        line_ending = line[len(content) :]
        fence_match = re.match(r" {0,3}(`{3,}|~{3,})", content)
        if fence_character is not None:
            if re.fullmatch(
                rf" {{0,3}}{re.escape(fence_character)}{{{fence_length},}}[ \t]*",
                content,
            ):
                fence_character = None
                fence_length = 0
            result.append(line_ending)
            continue
        if fence_match is not None:
            fence_character = fence_match.group(1)[0]
            fence_length = len(fence_match.group(1))
            result.append(line_ending)
            continue
        result.append(line)

    markdown = "".join(result)
    without_inline_code = list(markdown)
    index = 0
    while index < len(markdown):
        if markdown[index] != "`":
            index += 1
            continue
        delimiter_end = index + 1
        while delimiter_end < len(markdown) and markdown[delimiter_end] == "`":
            delimiter_end += 1
        delimiter = markdown[index:delimiter_end]
        closing_index = markdown.find(delimiter, delimiter_end)
        if closing_index == -1:
            index = delimiter_end
            continue
        for code_index in range(index, closing_index + len(delimiter)):
            if without_inline_code[code_index] not in {"\r", "\n"}:
                without_inline_code[code_index] = " "
        index = closing_index + len(delimiter)
    return "".join(without_inline_code)


def has_active_readme_bare_ios_download_url(text: str) -> bool:
    return any(
        README_REFERENCE_DEFINITION_LINE_RE.match(line) is None
        and README_IOS_BARE_GITHUB_URL_RE.search(line) is not None
        for line in text.splitlines()
    )


def javascript_runtime_state(source: str) -> tuple[dict[str, Any] | None, str | None]:
    try:
        completed = subprocess.run(
            ["node", "--experimental-permission", "-e", JAVASCRIPT_RUNTIME_PROBE],
            input=source,
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
            env={"PATH": os.environ.get("PATH", "")},
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, str(error)
    if completed.returncode != 0:
        return None, completed.stderr.strip() or "Node runtime probe failed"
    try:
        state = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        return None, str(error)
    if not isinstance(state, dict):
        return None, "Node runtime probe did not return an object"
    return state, None


def runtime_has_unselected_ios_asset(state: dict[str, Any]) -> bool:
    release = state.get("release")
    if not isinstance(release, dict):
        return False
    assets = release.get("assets")
    if not isinstance(assets, dict):
        return False
    ios_assets = assets.get("ios")
    return isinstance(ios_assets, dict) and "ipa" in ios_assets


def runtime_has_active_ios_download(state: dict[str, Any]) -> bool:
    urls = state.get("urls")
    hrefs = state.get("hrefs")
    candidates = list(urls.values()) if isinstance(urls, dict) else []
    candidates.extend(hrefs if isinstance(hrefs, list) else [])
    return any(
        isinstance(candidate, str) and IOS_IPA_REFERENCE_RE.search(candidate) is not None
        for candidate in candidates
    )


def markdown_reference_key(label: str) -> str:
    return " ".join(label.casefold().split())


def readme_has_active_ios_download(text: str) -> bool:
    active_text = markdown_without_code(text)
    if (
        README_IOS_DOWNLOAD_ROW_RE.search(active_text) is not None
        or README_IOS_DOWNLOAD_LINK_RE.search(active_text) is not None
        or README_IOS_AUTOLINK_RE.search(active_text) is not None
        or has_active_readme_bare_ios_download_url(active_text)
        or any(
            IOS_IPA_REFERENCE_RE.search(href) is not None
            for href, _ in active_page_links(active_text)
        )
    ):
        return True
    reference_definitions = {
        markdown_reference_key(definition.group(1)): definition.group(2)
        for definition in README_REFERENCE_DEFINITION_RE.finditer(active_text)
    }
    reference_labels = [
        reference_link.group(2) or reference_link.group(1)
        for reference_link in README_REFERENCE_LINK_RE.finditer(active_text)
    ]
    reference_labels.extend(
        reference_link.group(1)
        for reference_link in README_SHORTCUT_REFERENCE_LINK_RE.finditer(active_text)
    )
    for label in reference_labels:
        destination = reference_definitions.get(markdown_reference_key(label))
        if destination is not None and IOS_IPA_REFERENCE_RE.search(destination) is not None:
            return True
    return False


def release_note_metadata_section(release_notes: str) -> str:
    metadata_heading = RELEASE_NOTE_METADATA_HEADING_RE.search(release_notes)
    if metadata_heading is None:
        return ""
    next_heading = RELEASE_NOTE_SECTION_HEADING_RE.search(release_notes, metadata_heading.end())
    section_end = next_heading.start() if next_heading is not None else len(release_notes)
    return release_notes[metadata_heading.end() : section_end]


def release_note_asset_rows(version: str, platforms: tuple[str, ...]) -> list[str]:
    rows = {
        "macos": [f"- macOS DMG：`VoxFlow-{version}-macOS.dmg`"],
        "windows": [
            f"- Windows 安装包：`VoxFlow-{version}-windows-x64-setup.exe`",
            f"- Windows 便携包：`VoxFlow-{version}-windows-x64-portable.zip`",
        ],
        "ios": [f"- iOS Ad Hoc IPA：`Mashangxie-{version}-iOS.ipa`"],
    }
    return [row for platform in platforms for row in rows[platform]]


def release_note_bundle_rows(version: str, build: str) -> list[tuple[str, str, re.Pattern[str]]]:
    return [
        (
            "version",
            f"- `CFBundleShortVersionString`：{version}",
            RELEASE_NOTE_VERSION_ROW_RE,
        ),
        (
            "build",
            f"- `CFBundleVersion`：{build}",
            RELEASE_NOTE_BUILD_ROW_RE,
        ),
    ]


def main() -> int:
    version, build = read_version()
    tag = f"v{version}"
    release_download_base = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}"
    failures: list[str] = []

    ios_project = read_text(IOS_PROJECT)
    require(
        ios_project.count(f'CFBundleShortVersionString: "{version}"') == 2,
        "Apps/VoxFlowiOS/project.yml versions are stale",
        failures,
    )
    require(
        ios_project.count(f'CFBundleVersion: "{build}"') == 2,
        "Apps/VoxFlowiOS/project.yml builds are stale",
        failures,
    )
    for info_plist in IOS_INFO_PLISTS:
        with info_plist.open("rb") as handle:
            ios_plist = plistlib.load(handle)
        require(
            str(ios_plist.get("CFBundleShortVersionString")) == version,
            f"{info_plist.relative_to(ROOT)} version is stale",
            failures,
        )
        require(
            str(ios_plist.get("CFBundleVersion")) == build,
            f"{info_plist.relative_to(ROOT)} build is stale",
            failures,
        )

    for element, expected in (
        ("Version", version),
        ("AssemblyVersion", f"{version}.0"),
        ("FileVersion", f"{version}.0"),
    ):
        require(
            read_windows_project_value(element) == expected,
            f"{WINDOWS_PROJECT.relative_to(ROOT)} <{element}> is stale (expected {expected})",
            failures,
        )

    release_notes_path = ROOT / f".github/release-notes/{tag}.md"
    require(release_notes_path.exists(), f"missing release notes for {tag}", failures)
    release_notes = ""
    release_notes_summary = ""
    if release_notes_path.exists():
        release_notes = read_text(release_notes_path)
        release_notes_summary = next(
            (
                re.sub(r"^[-*]\s+", "", line.strip())
                for line in release_notes.splitlines()
                if line.strip() and not line.strip().startswith("#")
            ),
            "",
        )

    try:
        loaded_release_json = json.loads(read_text(ROOT / "docs/release.json"))
    except json.JSONDecodeError as error:
        failures.append(f"docs/release.json is invalid JSON: {error}")
        release_json: dict[str, Any] = {}
    else:
        if not isinstance(loaded_release_json, dict):
            failures.append("docs/release.json must contain an object")
            release_json = {}
        else:
            release_json = loaded_release_json

    try:
        platforms = validate_release_assets(release_json, location="docs/release.json")
    except PlatformContractError as error:
        failures.append(f"docs/release.json platform declaration is invalid: {error}")
        platforms: tuple[str, ...] = ()

    expected_assets = selected_assets(version, platforms)
    expected_asset_names = [name for _, _, name in expected_assets]

    if release_notes_path.exists():
        release_note_metadata = release_note_metadata_section(release_notes)
        for field, expected_row, pattern in release_note_bundle_rows(version, build):
            actual_rows = [match.group(0) for match in pattern.finditer(release_note_metadata)]
            require(
                actual_rows == [expected_row],
                f"release notes bundle {field} row is stale: {expected_row}",
                failures,
            )
        for asset_row in release_note_asset_rows(version, platforms):
            require(
                release_note_metadata.count(asset_row) == 1,
                f"release notes asset row is stale: {asset_row}",
                failures,
            )
        if "ios" not in platforms:
            require(
                RELEASE_NOTE_IOS_ASSET_ROW_RE.search(release_note_metadata) is None,
                "release notes have an unselected iOS IPA asset row",
                failures,
            )

    docs_script = read_text(ROOT / "docs/script.js")
    require(f'version: "{version}"' in docs_script, "docs/script.js release.version is stale", failures)
    require(f'tag: "{tag}"' in docs_script, "docs/script.js release.tag is stale", failures)
    require(
        f'assetName: "VoxFlow-{version}-macOS.dmg"' in docs_script,
        "docs/script.js release.assetName is stale",
        failures,
    )
    for asset_name in expected_asset_names:
        require(
            f'name: "{asset_name}"' in docs_script,
            f"docs/script.js asset reference is stale: {asset_name}",
            failures,
        )
    if "ios" in platforms:
        require(
            'distribution: "ad-hoc"' in docs_script,
            "docs/script.js iOS distribution must be ad-hoc",
            failures,
        )
    else:
        runtime_state, runtime_error = javascript_runtime_state(docs_script)
        require(
            runtime_state is not None,
            f"docs/script.js active runtime probe failed: {runtime_error}",
            failures,
        )
        if runtime_state is not None:
            require(
                not runtime_has_unselected_ios_asset(runtime_state),
                "docs/script.js has an unselected iOS IPA download configuration",
                failures,
            )
            require(
                not runtime_has_active_ios_download(runtime_state),
                "docs/script.js has an unselected iOS IPA href or download URL",
                failures,
            )

    docs_index = read_text(ROOT / "docs/index.html")
    for platform, kind, asset_name in expected_assets:
        if (platform, kind) not in {
            ("macos", "dmg"),
            ("windows", "installer"),
            ("ios", "ipa"),
        }:
            continue
        require(
            f"releases/download/{tag}/{asset_name}" in docs_index,
            f"docs/index.html {platform} download fallback is stale",
            failures,
        )
    if "ios" not in platforms:
        index_download_links = active_page_links(docs_index)
        require(
            all(
                IOS_IPA_REFERENCE_RE.search(href) is None for href, _ in index_download_links
            ),
            "docs/index.html has an unselected iOS IPA download reference",
            failures,
        )
        require(
            all(platform != "ios" for _, platform in index_download_links),
            "docs/index.html has an active unselected iOS download CTA",
            failures,
        )
    require(f"{tag} · Free & open source" in docs_index, "docs/index.html release note fallback is stale", failures)
    release_data = current_release_data(docs_index)
    require(release_data is not None, "docs/index.html release data fallback is missing or invalid", failures)
    if release_data is not None:
        current_release = next(
            (
                item
                for item in release_data
                if isinstance(item, dict) and item.get("tag_name") == tag
            ),
            None,
        )
        require(current_release is not None, "docs/index.html current release fallback is missing", failures)
        if current_release is not None:
            require(
                current_release.get("body", "").strip() == release_notes.strip(),
                "docs/index.html current release notes fallback is stale",
                failures,
            )

    dmg_name = release_asset_names(version)[("macos", "dmg")]
    require(release_json.get("version") == version, "docs/release.json version is stale", failures)
    require(release_json.get("tag") == tag, "docs/release.json tag is stale", failures)
    require(
        release_json.get("releaseNotes") == release_notes_summary,
        "docs/release.json releaseNotes summary is stale",
        failures,
    )
    require(release_json.get("assetName") == dmg_name, "docs/release.json assetName is stale", failures)
    require(
        release_json.get("releasePageURL") == f"https://github.com/xingbofeng/VoxFlow/releases/tag/{tag}",
        "docs/release.json releasePageURL is stale",
        failures,
    )
    require(
        release_json.get("downloadURL") == f"{release_download_base}/{dmg_name}",
        "docs/release.json downloadURL is stale",
        failures,
    )
    assets = release_json.get("assets")
    assets = assets if isinstance(assets, dict) else {}
    for platform, kind, asset_name in expected_assets:
        platform_assets = assets.get(platform)
        platform_assets = platform_assets if isinstance(platform_assets, dict) else {}
        asset = platform_assets.get(kind)
        asset = asset if isinstance(asset, dict) else {}
        require(
            asset.get("name") == asset_name,
            f"docs/release.json assets.{platform}.{kind}.name is stale",
            failures,
        )
        require(
            asset.get("downloadURL") == f"{release_download_base}/{asset_name}",
            f"docs/release.json assets.{platform}.{kind}.downloadURL is stale",
            failures,
        )
    if "ios" in platforms:
        ios_assets = assets.get("ios")
        ios_assets = ios_assets if isinstance(ios_assets, dict) else {}
        require(
            ios_assets.get("distribution") == "ad-hoc",
            "docs/release.json assets.ios.distribution must be ad-hoc",
            failures,
        )

    for relative in README_PATHS:
        text = read_text(ROOT / relative)
        for expected_asset in expected_asset_names:
            found = re.findall(re.escape(expected_asset), text)
            require(
                found == [expected_asset],
                f"{relative} asset reference is stale: {expected_asset} ({len(found)} found)",
                failures,
            )
        if "ios" not in platforms:
            require(
                not readme_has_active_ios_download(text),
                f"{relative} has an unselected iOS IPA download link",
                failures,
            )

    if os.environ.get("VOXFLOW_RELEASE_CHECK_REQUIRE_SENTRY") == "1":
        sentry_dsn = os.environ.get("VOXFLOW_SENTRY_DSN", "").strip()
        require(sentry_dsn, "VOXFLOW_SENTRY_DSN is required for production release builds", failures)
        require(os.environ.get("SENTRY_AUTH_TOKEN", "").strip(), "SENTRY_AUTH_TOKEN is required for dSYM upload", failures)
        require(os.environ.get("SENTRY_ORG", "").strip(), "SENTRY_ORG is required for dSYM upload", failures)
        require(os.environ.get("SENTRY_PROJECT", "").strip(), "SENTRY_PROJECT is required for dSYM upload", failures)
        require(
            (ROOT / "scripts/upload-sentry-dsym.sh").exists(),
            "scripts/upload-sentry-dsym.sh is required for dSYM upload",
            failures,
        )

    if failures:
        for failure in failures:
            print(f"release metadata check failed: {failure}", file=sys.stderr)
        return 1

    print(f"release metadata check passed for {tag} build metadata")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
