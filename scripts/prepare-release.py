#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

from release_platforms import PlatformContractError, parse_published_platforms


ROOT = Path(__file__).resolve().parents[1]
PLIST = ROOT / "Sources/VoxFlowApp/Resources/Info.plist"
IOS_PROJECT = ROOT / "Apps/VoxFlowiOS/project.yml"
IOS_INFO_PLISTS = [
    ROOT / "Apps/VoxFlowiOS/VoxFlowiOS/Info.plist",
    ROOT / "Apps/VoxFlowiOS/Keyboard/Info.plist",
]
WINDOWS_PROJECT = ROOT / "VoxFlow.Windows/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
TEMPLATE = ROOT / ".github/release-notes/TEMPLATE.md"
DEFAULT_PLATFORMS = ("macos", "windows", "ios")


def replace(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    new_text = re.sub(pattern, replacement, text)
    if new_text != text:
        path.write_text(new_text, encoding="utf-8")


def parse_platforms(value: str) -> tuple[str, ...]:
    try:
        return parse_published_platforms(value.split(","), location="--platforms")
    except PlatformContractError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def release_assets(version: str) -> dict[str, dict[str, object]]:
    tag = f"v{version}"
    release_download_base = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}"
    dmg = f"VoxFlow-{version}-macOS.dmg"
    windows_installer = f"VoxFlow-{version}-windows-x64-setup.exe"
    windows_portable = f"VoxFlow-{version}-windows-x64-portable.zip"
    ios_ipa = f"Mashangxie-{version}-iOS.ipa"
    return {
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
    }


def asset_name(assets: dict[str, dict[str, object]], platform: str, kind: str) -> str:
    asset = assets[platform][kind]
    assert isinstance(asset, dict)
    name = asset["name"]
    assert isinstance(name, str)
    return name


def asset_download_url(assets: dict[str, dict[str, object]], platform: str, kind: str) -> str:
    asset = assets[platform][kind]
    assert isinstance(asset, dict)
    url = asset["downloadURL"]
    assert isinstance(url, str)
    return url


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


def update_windows_project(version: str) -> None:
    for element, value in (
        ("Version", version),
        ("AssemblyVersion", f"{version}.0"),
        ("FileVersion", f"{version}.0"),
    ):
        replace(
            WINDOWS_PROJECT,
            rf"(<{element}>)[^<]+(</{element}>)",
            rf"\g<1>{value}\2",
        )


def release_note_asset_lines(version: str, platforms: tuple[str, ...]) -> str:
    asset_lines = {
        "macos": f"- macOS DMG：`VoxFlow-{version}-macOS.dmg`",
        "windows": "\n".join(
            (
                f"- Windows 安装包：`VoxFlow-{version}-windows-x64-setup.exe`",
                f"- Windows 便携包：`VoxFlow-{version}-windows-x64-portable.zip`",
            )
        ),
        "ios": f"- iOS Ad Hoc IPA：`Mashangxie-{version}-iOS.ipa`",
    }
    return "\n".join(asset_lines[platform] for platform in platforms)


def ensure_release_notes(version: str, build: str, platforms: tuple[str, ...]) -> None:
    target = ROOT / f".github/release-notes/v{version}.md"
    if target.exists():
        return
    text = TEMPLATE.read_text(encoding="utf-8")
    text = text.replace("VERSION", version).replace("BUILD", build)
    text = text.replace("ASSET_LINES", release_note_asset_lines(version, platforms))
    target.write_text(text, encoding="utf-8")


def update_index_release_fallback(version: str) -> None:
    index = ROOT / "docs/index.html"
    index_text = index.read_text(encoding="utf-8")
    start_marker = '<script id="voxflow-release-data" type="application/json">'
    end_marker = "</script>"
    start = index_text.find(start_marker)
    if start == -1:
        raise RuntimeError("docs/index.html release data fallback is missing")
    start += len(start_marker)
    end = index_text.find(end_marker, start)
    if end == -1:
        raise RuntimeError("docs/index.html release data fallback is incomplete")

    try:
        historical_releases = json.loads(index_text[start:end])
    except json.JSONDecodeError as error:
        raise RuntimeError("docs/index.html release data fallback is invalid JSON") from error
    if not isinstance(historical_releases, list):
        raise RuntimeError("docs/index.html release data fallback must be a list")

    tag = f"v{version}"
    release_notes = (ROOT / f".github/release-notes/{tag}.md").read_text(encoding="utf-8")
    current_release = {
        "tag_name": tag,
        "name": f"VoxFlow {version}",
        "body": release_notes,
        "html_url": f"https://github.com/xingbofeng/VoxFlow/releases/tag/{tag}",
        "published_at": "",
    }
    retained_releases = [
        item
        for item in historical_releases
        if isinstance(item, dict) and item.get("tag_name") != tag
    ]
    fallback = json.dumps([current_release, *retained_releases][:3], ensure_ascii=False, indent=2)
    safe_fallback = fallback.replace("</", "<\\/")
    index.write_text(
        index_text[:start] + "\n" + safe_fallback + "\n  " + index_text[end:],
        encoding="utf-8",
    )


def update_docs(version: str, platforms: tuple[str, ...]) -> None:
    tag = f"v{version}"
    assets = release_assets(version)
    dmg = asset_name(assets, "macos", "dmg")
    windows_installer = asset_name(assets, "windows", "installer")
    windows_portable = asset_name(assets, "windows", "portable")
    ios_ipa = asset_name(assets, "ios", "ipa")

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
    if "ios" in platforms:
        replace(script, r'name: "Mashangxie-[^"]+-iOS\.ipa"', f'name: "{ios_ipa}"')

    index = ROOT / "docs/index.html"
    replace(
        index,
        r"https://github\.com/xingbofeng/VoxFlow/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-macOS\.dmg",
        asset_download_url(assets, "macos", "dmg"),
    )
    replace(
        index,
        r"https://github\.com/xingbofeng/VoxFlow/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-setup\.exe",
        asset_download_url(assets, "windows", "installer"),
    )
    if "ios" in platforms:
        replace(
            index,
            r"https://github\.com/xingbofeng/VoxFlow/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa",
            asset_download_url(assets, "ios", "ipa"),
        )
    replace(index, r"v[0-9]+\.[0-9]+\.[0-9]+ · Free & open source", f"{tag} · Free & open source")

    update_index_release_fallback(version)

    release_json = {
        "version": version,
        "tag": tag,
        "assetName": dmg,
        "releasePageURL": f"https://github.com/xingbofeng/VoxFlow/releases/tag/{tag}",
        "downloadURL": asset_download_url(assets, "macos", "dmg"),
        "publishedPlatforms": list(platforms),
        "assets": {platform: assets[platform] for platform in platforms},
        "releaseNotes": release_notes_summary(version),
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


def update_readmes(version: str, platforms: tuple[str, ...]) -> None:
    assets = release_assets(version)
    dmg = asset_name(assets, "macos", "dmg")
    windows_installer = asset_name(assets, "windows", "installer")
    windows_portable = asset_name(assets, "windows", "portable")
    ios_ipa = asset_name(assets, "ios", "ipa")
    for relative in ["README.md", "README.zh-CN.md", "README.zh-TW.md", "README.ja.md", "README.ko.md"]:
        path = ROOT / relative
        replace(path, r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-macOS\.dmg", dmg)
        replace(
            path,
            r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-setup\.exe",
            windows_installer,
        )
        replace(
            path,
            r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-portable\.zip",
            windows_portable,
        )
        if "ios" in platforms:
            replace(path, r"Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa", ios_ipa)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument(
        "--platforms",
        type=parse_platforms,
        default=DEFAULT_PLATFORMS,
        help="comma-separated release platforms (macos,windows or macos,windows,ios)",
    )
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        raise SystemExit("--version must look like 1.6.2")
    if not re.fullmatch(r"[0-9]+", args.build):
        raise SystemExit("--build must be an integer")

    update_plist(args.version, args.build)
    update_ios_project(args.version, args.build)
    update_windows_project(args.version)
    ensure_release_notes(args.version, args.build, args.platforms)
    update_docs(args.version, args.platforms)
    update_readmes(args.version, args.platforms)
    print(
        "prepared VoxFlow release "
        f"v{args.version} build {args.build} for {','.join(args.platforms)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
