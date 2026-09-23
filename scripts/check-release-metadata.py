#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import plistlib
import re
import sys
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
        for asset_name in expected_asset_names:
            require(
                asset_name in release_notes,
                f"release notes asset reference is stale: {asset_name}",
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
