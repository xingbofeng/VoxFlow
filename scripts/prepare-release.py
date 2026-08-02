#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLIST = ROOT / "Sources/VoxFlowApp/Resources/Info.plist"
IOS_PROJECT = ROOT / "Apps/VoxFlowiOS/project.yml"
IOS_INFO_PLISTS = [
    ROOT / "Apps/VoxFlowiOS/VoxFlowiOS/Info.plist",
    ROOT / "Apps/VoxFlowiOS/Keyboard/Info.plist",
]
TEMPLATE = ROOT / ".github/release-notes/TEMPLATE.md"


def replace(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    new_text = re.sub(pattern, replacement, text)
    if new_text != text:
        path.write_text(new_text, encoding="utf-8")


def update_plist(version: str, build: str) -> None:
    replace(
        PLIST,
        r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
        rf"\g<1>{version}\2",
    )
    replace(
        PLIST,
        r"(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)",
        rf"\g<1>{build}\2",
    )


def update_ios_project(version: str, build: str) -> None:
    replace(
        IOS_PROJECT,
        r'(CFBundleShortVersionString: ")[^"]+(")',
        rf"\g<1>{version}\2",
    )
    replace(
        IOS_PROJECT,
        r'(CFBundleVersion: ")[^"]+(")',
        rf"\g<1>{build}\2",
    )
    for info_plist in IOS_INFO_PLISTS:
        replace(
            info_plist,
            r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
            rf"\g<1>{version}\2",
        )
        replace(
            info_plist,
            r"(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)",
            rf"\g<1>{build}\2",
        )


def ensure_release_notes(version: str, build: str) -> None:
    target = ROOT / f".github/release-notes/v{version}.md"
    if target.exists():
        return
    text = TEMPLATE.read_text(encoding="utf-8")
    text = text.replace("VERSION", version).replace("BUILD", build)
    target.write_text(text, encoding="utf-8")


def update_docs(version: str) -> None:
    tag = f"v{version}"
    dmg = f"VoxFlow-{version}-macOS.dmg"
    windows_installer = f"VoxFlow-{version}-windows-x64-setup.exe"
    windows_portable = f"VoxFlow-{version}-windows-x64-portable.zip"
    ios_ipa = f"Mashangxie-{version}-iOS.ipa"
    release_download_base = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}"

    script = ROOT / "docs/script.js"
    replace(script, r'version: "[^"]+"', f'version: "{version}"')
    replace(script, r'tag: "v[^"]+"', f'tag: "{tag}"')
    replace(script, r'assetName: "VoxFlow-[^"]+-macOS\.dmg"', f'assetName: "{dmg}"')
    replace(script, r'name: "VoxFlow-[^"]+-macOS\.dmg"', f'name: "{dmg}"')
    replace(
        script,
        r'name: "VoxFlow-[^"]+-windows-x64-setup\.exe"',
        f'name: "{windows_installer}"',
    )
    replace(
        script,
        r'name: "VoxFlow-[^"]+-windows-x64-portable\.zip"',
        f'name: "{windows_portable}"',
    )
    replace(script, r'name: "Mashangxie-[^"]+-iOS\.ipa"', f'name: "{ios_ipa}"')

    index = ROOT / "docs/index.html"
    release_url = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}/{dmg}"
    replace(
        index,
        r"https://github\.com/xingbofeng/VoxFlow/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-macOS\.dmg",
        release_url,
    )
    replace(
        index,
        r"https://github\.com/xingbofeng/VoxFlow/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-setup\.exe",
        f"{release_download_base}/{windows_installer}",
    )
    replace(
        index,
        r"https://github\.com/xingbofeng/VoxFlow/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa",
        f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}/{ios_ipa}",
    )
    replace(index, r"v[0-9]+\.[0-9]+\.[0-9]+ · Free & open source", f"{tag} · Free & open source")

    release_notes = release_notes_summary(version)
    release_json = {
        "version": version,
        "tag": tag,
        "assetName": dmg,
        "releasePageURL": f"https://github.com/xingbofeng/VoxFlow/releases/tag/{tag}",
        "downloadURL": release_url,
        "assets": {
            "macos": {
                "dmg": {
                    "name": dmg,
                    "downloadURL": f"{release_download_base}/{dmg}",
                }
            },
            "windows": {
                "installer": {
                    "name": windows_installer,
                    "downloadURL": f"{release_download_base}/{windows_installer}",
                },
                "portable": {
                    "name": windows_portable,
                    "downloadURL": f"{release_download_base}/{windows_portable}",
                },
            },
            "ios": {
                "ipa": {
                    "name": ios_ipa,
                    "downloadURL": f"{release_download_base}/{ios_ipa}",
                },
                "distribution": "ad-hoc",
            },
        },
        "releaseNotes": release_notes,
        "draft": False,
        "prerelease": False,
    }
    (ROOT / "docs/release.json").write_text(
        json.dumps(release_json, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def release_notes_summary(version: str) -> str:
    path = ROOT / f".github/release-notes/v{version}.md"
    if not path.exists():
        return ""
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            return re.sub(r"^[-*]\s+", "", stripped)
    return ""


def update_readmes(version: str) -> None:
    dmg = f"VoxFlow-{version}-macOS.dmg"
    windows_installer = f"VoxFlow-{version}-windows-x64-setup.exe"
    windows_portable = f"VoxFlow-{version}-windows-x64-portable.zip"
    ios_ipa = f"Mashangxie-{version}-iOS.ipa"
    for relative in ["README.md", "README.zh-CN.md", "README.zh-TW.md", "README.ja.md", "README.ko.md"]:
        replace(ROOT / relative, r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-macOS\.dmg", dmg)
        replace(
            ROOT / relative,
            r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-setup\.exe",
            windows_installer,
        )
        replace(
            ROOT / relative,
            r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-portable\.zip",
            windows_portable,
        )
        replace(ROOT / relative, r"Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa", ios_ipa)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        raise SystemExit("--version must look like 1.6.2")
    if not re.fullmatch(r"[0-9]+", args.build):
        raise SystemExit("--build must be an integer")

    update_plist(args.version, args.build)
    update_ios_project(args.version, args.build)
    ensure_release_notes(args.version, args.build)
    update_docs(args.version)
    update_readmes(args.version)
    print(f"prepared VoxFlow release v{args.version} build {args.build}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
