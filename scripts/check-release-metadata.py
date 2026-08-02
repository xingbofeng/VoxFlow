#!/usr/bin/env python3
import plistlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLIST = ROOT / "Sources/VoxFlowApp/Resources/Info.plist"
IOS_PROJECT = ROOT / "Apps/VoxFlowiOS/project.yml"
IOS_INFO_PLISTS = [
    ROOT / "Apps/VoxFlowiOS/VoxFlowiOS/Info.plist",
    ROOT / "Apps/VoxFlowiOS/Keyboard/Info.plist",
]


def read_version() -> tuple[str, str]:
    with PLIST.open("rb") as handle:
        plist = plistlib.load(handle)
    return str(plist["CFBundleShortVersionString"]), str(plist["CFBundleVersion"])


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    version, build = read_version()
    tag = f"v{version}"
    dmg_name = f"VoxFlow-{version}-macOS.dmg"
    windows_installer_name = f"VoxFlow-{version}-windows-x64-setup.exe"
    windows_portable_name = f"VoxFlow-{version}-windows-x64-portable.zip"
    ios_ipa_name = f"Mashangxie-{version}-iOS.ipa"
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

    require(
        (ROOT / f".github/release-notes/{tag}.md").exists(),
        f"missing release notes for {tag}",
        failures,
    )

    docs_script = read_text(ROOT / "docs/script.js")
    require(f'version: "{version}"' in docs_script, "docs/script.js release.version is stale", failures)
    require(f'tag: "{tag}"' in docs_script, "docs/script.js release.tag is stale", failures)
    require(
        f'assetName: "{dmg_name}"' in docs_script,
        "docs/script.js release.assetName is stale",
        failures,
    )
    for asset_name in [dmg_name, windows_installer_name, windows_portable_name, ios_ipa_name]:
        require(
            f'name: "{asset_name}"' in docs_script,
            f"docs/script.js asset reference is stale: {asset_name}",
            failures,
        )
    require(
        'distribution: "ad-hoc"' in docs_script,
        "docs/script.js iOS distribution must be ad-hoc",
        failures,
    )

    docs_index = read_text(ROOT / "docs/index.html")
    require(
        f"releases/download/{tag}/{dmg_name}" in docs_index,
        "docs/index.html download fallback is stale",
        failures,
    )
    require(
        f"releases/download/{tag}/{windows_installer_name}" in docs_index,
        "docs/index.html Windows download fallback is stale",
        failures,
    )
    require(
        f"releases/download/{tag}/{ios_ipa_name}" in docs_index,
        "docs/index.html iOS download fallback is stale",
        failures,
    )
    require(f"{tag} · Free & open source" in docs_index, "docs/index.html release note fallback is stale", failures)

    release_json = json.loads(read_text(ROOT / "docs/release.json"))
    require(release_json.get("version") == version, "docs/release.json version is stale", failures)
    require(release_json.get("tag") == tag, "docs/release.json tag is stale", failures)
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
    assets = release_json.get("assets", {})
    expected_assets = {
        ("macos", "dmg"): dmg_name,
        ("windows", "installer"): windows_installer_name,
        ("windows", "portable"): windows_portable_name,
        ("ios", "ipa"): ios_ipa_name,
    }
    for (platform, kind), asset_name in expected_assets.items():
        asset = assets.get(platform, {}).get(kind, {})
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
    require(
        assets.get("ios", {}).get("distribution") == "ad-hoc",
        "docs/release.json assets.ios.distribution must be ad-hoc",
        failures,
    )

    for relative in ["README.md", "README.zh-CN.md", "README.zh-TW.md", "README.ja.md", "README.ko.md"]:
        text = read_text(ROOT / relative)
        expected_readme_assets = [dmg_name, windows_installer_name, windows_portable_name, ios_ipa_name]
        for expected_asset in expected_readme_assets:
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
