#!/usr/bin/env python3
import plistlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLIST = ROOT / "Sources/VoxFlowApp/Resources/Info.plist"


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
    version, _build = read_version()
    tag = f"v{version}"
    dmg_name = f"VoxFlow-{version}-macOS.dmg"
    failures: list[str] = []

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

    docs_index = read_text(ROOT / "docs/index.html")
    require(
        f"releases/download/{tag}/{dmg_name}" in docs_index,
        "docs/index.html download fallback is stale",
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
        release_json.get("downloadURL") == f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}/{dmg_name}",
        "docs/release.json downloadURL is stale",
        failures,
    )

    for relative in ["README.md", "README.zh-CN.md", "README.zh-TW.md", "README.ja.md", "README.ko.md"]:
        text = read_text(ROOT / relative)
        found = re.findall(r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-macOS\.dmg", text)
        require(found == [dmg_name], f"{relative} DMG reference is stale: {found}", failures)

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
