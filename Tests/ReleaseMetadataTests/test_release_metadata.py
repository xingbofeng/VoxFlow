#!/usr/bin/env python3
"""End-to-end behavior checks for release metadata preparation and validation."""

from __future__ import annotations

import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PREPARE_RELEASE = Path("scripts/prepare-release.py")
CHECK_RELEASE_METADATA = Path("scripts/check-release-metadata.py")
WINDOWS_PROJECT = Path("VoxFlow.Windows/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj")
MACOS_PLIST = Path("Sources/VoxFlowApp/Resources/Info.plist")
IOS_PROJECT = Path("Apps/VoxFlowiOS/project.yml")
IOS_INFO_PLISTS = (
    Path("Apps/VoxFlowiOS/VoxFlowiOS/Info.plist"),
    Path("Apps/VoxFlowiOS/Keyboard/Info.plist"),
)
README_PATHS = (
    Path("README.md"),
    Path("README.zh-CN.md"),
    Path("README.zh-TW.md"),
    Path("README.ja.md"),
    Path("README.ko.md"),
)


def copy_fixture_file(fixture_root: Path, relative_path: Path) -> None:
    source = ROOT / relative_path
    destination = fixture_root / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def create_fixture(fixture_root: Path) -> None:
    fixture_files = (
        PREPARE_RELEASE,
        CHECK_RELEASE_METADATA,
        Path("scripts/release_platforms.py"),
        MACOS_PLIST,
        IOS_PROJECT,
        *IOS_INFO_PLISTS,
        WINDOWS_PROJECT,
        Path(".github/release-notes/TEMPLATE.md"),
        Path("docs/release.json"),
        Path("docs/script.js"),
        Path("docs/index.html"),
        *README_PATHS,
    )
    for relative_path in fixture_files:
        copy_fixture_file(fixture_root, relative_path)


def run_script(
    fixture_root: Path,
    script: Path,
    *arguments: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(fixture_root / script), *arguments],
        cwd=fixture_root,
        check=False,
        capture_output=True,
        text=True,
    )


def plist_values(path: Path) -> tuple[str, str]:
    with path.open("rb") as handle:
        metadata = plistlib.load(handle)
    return (
        str(metadata["CFBundleShortVersionString"]),
        str(metadata["CFBundleVersion"]),
    )


def project_value(path: Path, element: str) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(rf"<{element}>\s*([^<]+?)\s*</{element}>", text)
    if match is None:
        raise AssertionError(f"{element} is missing from {path}")
    return match.group(1).strip()


def update_current_release_fallback_body(index_path: Path, tag: str, body: str) -> None:
    index = index_path.read_text(encoding="utf-8")
    release_data_match = re.search(
        r'<script id="voxflow-release-data" type="application/json">\s*(.*?)\s*</script>',
        index,
        re.DOTALL,
    )
    if release_data_match is None:
        raise AssertionError("release data fallback is missing")
    releases = json.loads(release_data_match.group(1))
    if not isinstance(releases, list):
        raise AssertionError("release data fallback must be a list")
    for release in releases:
        if isinstance(release, dict) and release.get("tag_name") == tag:
            release["body"] = body
            break
    else:
        raise AssertionError(f"release data fallback is missing {tag}")
    fallback = json.dumps(releases, ensure_ascii=False, indent=2).replace("</", "<\\/")
    index_path.write_text(
        index[: release_data_match.start(1)] + fallback + index[release_data_match.end(1) :],
        encoding="utf-8",
    )


class ReleaseMetadataTests(unittest.TestCase):
    version = "9.8.7"
    build = "42"

    def prepare(
        self,
        fixture_root: Path,
        platforms: str | None = None,
        version: str | None = None,
        build: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        arguments = ("--version", version or self.version, "--build", build or self.build)
        if platforms is not None:
            arguments += ("--platforms", platforms)
        return run_script(fixture_root, PREPARE_RELEASE, *arguments)

    def assert_source_versions_are_synchronized(self, fixture_root: Path) -> None:
        self.assertEqual(
            plist_values(fixture_root / MACOS_PLIST),
            (self.version, self.build),
        )

        ios_project = (fixture_root / IOS_PROJECT).read_text(encoding="utf-8")
        self.assertEqual(
            ios_project.count(f'CFBundleShortVersionString: "{self.version}"'),
            2,
        )
        self.assertEqual(ios_project.count(f'CFBundleVersion: "{self.build}"'), 2)
        for relative_path in IOS_INFO_PLISTS:
            self.assertEqual(
                plist_values(fixture_root / relative_path),
                (self.version, self.build),
            )

        windows_project = fixture_root / WINDOWS_PROJECT
        self.assertEqual(project_value(windows_project, "Version"), self.version)
        self.assertEqual(
            project_value(windows_project, "AssemblyVersion"),
            f"{self.version}.0",
        )
        self.assertEqual(
            project_value(windows_project, "FileVersion"),
            f"{self.version}.0",
        )

    def test_macos_and_windows_preparation_omits_ios_assets_and_syncs_sources(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)

            completed = self.prepare(fixture_root, "macos,windows")

            self.assertEqual(completed.returncode, 0, completed.stderr)
            release = json.loads((fixture_root / "docs/release.json").read_text(encoding="utf-8"))
            self.assertEqual(release["publishedPlatforms"], ["macos", "windows"])
            self.assertEqual(set(release["assets"]), {"macos", "windows"})
            self.assertNotIn("ios", release["assets"])
            downloads = [
                asset["downloadURL"]
                for platform in release["assets"].values()
                for asset in platform.values()
                if isinstance(asset, dict) and "downloadURL" in asset
            ]
            self.assertEqual(len(downloads), 3)

            self.assert_source_versions_are_synchronized(fixture_root)
            ios_ipa = f"Mashangxie-{self.version}-iOS.ipa"
            script = fixture_root / "docs/script.js"
            index = fixture_root / "docs/index.html"
            release_notes = (fixture_root / f".github/release-notes/v{self.version}.md").read_text(
                encoding="utf-8"
            )
            script_text = script.read_text(encoding="utf-8")
            self.assertNotIn(ios_ipa, release_notes)
            self.assertNotIn(ios_ipa, script_text)
            self.assertNotIn("release.assets.ios", script_text)
            self.assertNotIn(ios_ipa, index.read_text(encoding="utf-8"))
            self.assertIn("Mashangxie-1.15.0-iOS.ipa", index.read_text(encoding="utf-8"))
            self.assertNotIn('data-download-platform="ios"', index.read_text(encoding="utf-8"))
            for relative_path in README_PATHS:
                self.assertNotIn(ios_ipa, (fixture_root / relative_path).read_text(encoding="utf-8"))

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_default_preparation_preserves_three_platform_ios_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            first_preparation = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(first_preparation.returncode, 0, first_preparation.stderr)
            restored_version = "9.8.8"

            completed = self.prepare(fixture_root, version=restored_version)

            self.assertEqual(completed.returncode, 0, completed.stderr)
            release = json.loads((fixture_root / "docs/release.json").read_text(encoding="utf-8"))
            self.assertEqual(release["publishedPlatforms"], ["macos", "windows", "ios"])
            ios = release["assets"]["ios"]
            self.assertEqual(ios["distribution"], "ad-hoc")
            self.assertEqual(ios["ipa"]["name"], f"Mashangxie-{restored_version}-iOS.ipa")
            ios_ipa = f"Mashangxie-{restored_version}-iOS.ipa"
            release_notes = (fixture_root / f".github/release-notes/v{restored_version}.md").read_text(
                encoding="utf-8"
            )
            self.assertIn(ios_ipa, release_notes)
            script = fixture_root / "docs/script.js"
            index = fixture_root / "docs/index.html"
            script_text = script.read_text(encoding="utf-8")
            self.assertIn(ios_ipa, script_text)
            self.assertIn(
                "releaseDownloadURLs.ios = releaseAssetURL(release.assets.ios.ipa.name);",
                script_text,
            )
            self.assertIn(ios_ipa, index.read_text(encoding="utf-8"))
            self.assertIn('data-download-platform="ios"', index.read_text(encoding="utf-8"))
            for relative_path in README_PATHS:
                self.assertIn(ios_ipa, (fixture_root / relative_path).read_text(encoding="utf-8"))

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_same_version_preparation_restores_ios_release_note_asset_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            first_preparation = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(first_preparation.returncode, 0, first_preparation.stderr)

            release_notes_path = fixture_root / f".github/release-notes/v{self.version}.md"
            user_detail = "- 用户保留的发布说明：这条说明不应被准备脚本覆盖。"
            release_notes_path.write_text(
                release_notes_path.read_text(encoding="utf-8").replace(
                    "- 体验：",
                    f"- 体验：\n{user_detail}",
                    1,
                ),
                encoding="utf-8",
            )

            completed = self.prepare(fixture_root, "macos,windows,ios")

            self.assertEqual(completed.returncode, 0, completed.stderr)
            release_notes = release_notes_path.read_text(encoding="utf-8")
            self.assertIn(user_detail, release_notes)
            self.assertIn(f"Mashangxie-{self.version}-iOS.ipa", release_notes)
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_same_version_preparation_removes_ios_release_note_asset_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            first_preparation = self.prepare(fixture_root, "macos,windows,ios")
            self.assertEqual(first_preparation.returncode, 0, first_preparation.stderr)

            release_notes_path = fixture_root / f".github/release-notes/v{self.version}.md"
            historical_ipa = "Mashangxie-1.15.0-iOS.ipa"
            user_detail = f"- 用户保留的历史说明：`{historical_ipa}` 并非当前下载入口。"
            release_notes_path.write_text(
                release_notes_path.read_text(encoding="utf-8").replace(
                    "- 体验：",
                    f"- 体验：\n{user_detail}",
                    1,
                ),
                encoding="utf-8",
            )

            completed = self.prepare(fixture_root, "macos,windows")

            self.assertEqual(completed.returncode, 0, completed.stderr)
            release_notes = release_notes_path.read_text(encoding="utf-8")
            self.assertIn(user_detail, release_notes)
            self.assertNotIn(f"Mashangxie-{self.version}-iOS.ipa", release_notes)
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_same_version_preparation_normalizes_release_note_bundle_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            first_preparation = self.prepare(fixture_root, "macos,windows", build="41")
            self.assertEqual(first_preparation.returncode, 0, first_preparation.stderr)

            release_notes_path = fixture_root / f".github/release-notes/v{self.version}.md"
            user_detail = "- 用户保留的发布说明：这条说明不应被准备脚本覆盖。"
            release_notes_path.write_text(
                release_notes_path.read_text(encoding="utf-8")
                .replace(
                    "- 体验：",
                    f"- 体验：\n{user_detail}",
                    1,
                )
                .replace(
                    f"- `CFBundleShortVersionString`：{self.version}",
                    "- `CFBundleShortVersionString`：9.8.6",
                    1,
                )
                .replace(
                    "- `CFBundleVersion`：41",
                    "- `CFBundleVersion`：40",
                    1,
                ),
                encoding="utf-8",
            )

            completed = self.prepare(fixture_root, "macos,windows", build=self.build)

            self.assertEqual(completed.returncode, 0, completed.stderr)
            release_notes = release_notes_path.read_text(encoding="utf-8")
            self.assertIn(user_detail, release_notes)
            self.assertEqual(
                release_notes.count(f"- `CFBundleShortVersionString`：{self.version}"),
                1,
            )
            self.assertEqual(release_notes.count(f"- `CFBundleVersion`：{self.build}"), 1)
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_release_metadata_check_rejects_stale_release_note_bundle_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            release_notes_path = fixture_root / f".github/release-notes/v{self.version}.md"
            release_notes_path.write_text(
                release_notes_path.read_text(encoding="utf-8")
                .replace(
                    f"- `CFBundleShortVersionString`：{self.version}",
                    "- `CFBundleShortVersionString`：9.8.6",
                    1,
                ),
                encoding="utf-8",
            )
            update_current_release_fallback_body(
                fixture_root / "docs/index.html",
                f"v{self.version}",
                release_notes_path.read_text(encoding="utf-8"),
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("release notes bundle version", checked.stderr)

    def test_preparation_rejects_noncanonical_platform_order(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)

            completed = self.prepare(fixture_root, "windows,macos")

            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("--platforms", completed.stderr)

    def test_release_metadata_check_rejects_windows_version_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            windows_project = fixture_root / WINDOWS_PROJECT
            windows_project.write_text(
                windows_project.read_text(encoding="utf-8").replace(
                    f"<Version>{self.version}</Version>",
                    "<Version>9.8.8</Version>",
                    1,
                ),
                encoding="utf-8",
            )
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("VoxFlow.Windows", checked.stderr)
            self.assertIn("<Version>", checked.stderr)

    def test_release_metadata_check_rejects_unselected_ios_download_reference(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_tag = "v1.15.0"
            stale_ios_ipa = "Mashangxie-1.15.0-iOS.ipa"
            index = fixture_root / "docs/index.html"
            index.write_text(
                index.read_text(encoding="utf-8")
                .replace(
                    "<!-- RELEASE_IOS_HERO_CTA_BEGIN -->",
                    "<!-- RELEASE_IOS_HERO_CTA_BEGIN -->\n"
                    f'          <a href="https://github.com/xingbofeng/VoxFlow/releases/download/{stale_tag}/{stale_ios_ipa}">iOS</a>',
                    1,
                ),
                encoding="utf-8",
            )
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_unselected_ios_download_urls_on_active_surfaces(self) -> None:
        stale_tag = "v1.15.0"
        stale_ios_ipa = "Mashangxie-1.15.0-iOS.ipa"
        stale_download_url = (
            f"https://github.com/xingbofeng/VoxFlow/releases/download/{stale_tag}/{stale_ios_ipa}"
        )

        for relative_path, add_active_download in (
            (
                Path("docs/script.js"),
                lambda text: text.replace(
                    "const siteURL = ",
                    f'releaseDownloadURLs.ios = "{stale_download_url}";\n\nconst siteURL = ',
                    1,
                ),
            ),
            *(
                (
                    relative_path,
                    lambda text: text + f"\n| iOS 17+ | [Download iOS IPA]({stale_download_url}) | stale active CTA |\n",
                )
                for relative_path in README_PATHS
            ),
        ):
            with self.subTest(relative_path=relative_path), tempfile.TemporaryDirectory() as temporary_directory:
                fixture_root = Path(temporary_directory)
                create_fixture(fixture_root)
                prepared = self.prepare(fixture_root, "macos,windows")
                self.assertEqual(prepared.returncode, 0, prepared.stderr)

                target = fixture_root / relative_path
                target.write_text(add_active_download(target.read_text(encoding="utf-8")), encoding="utf-8")
                checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

                self.assertNotEqual(checked.returncode, 0)
                self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_new_url_ios_download_reference(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8").replace(
                    "const siteURL = ",
                    f'releaseDownloadURLs.ios = new URL("{stale_download_url}");\n\nconst siteURL = ',
                    1,
                ),
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_ios_entry_in_download_map(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8").replace(
                    "const siteURL = ",
                    f'const releaseDownloadURLs = {{ ios: "{stale_download_url}" }};\n\nconst siteURL = ',
                    1,
                ),
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_computed_ios_download_map_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8").replace(
                    "const siteURL = ",
                    'const iosPlatform = "ios";\n'
                    f'const staleDownload = "{stale_download_url}";\n'
                    "releaseDownloadURLs[iosPlatform] = staleDownload;\n\n"
                    "const siteURL = ",
                    1,
                ),
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_computed_ios_release_asset_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8").replace(
                    "const siteURL = ",
                    'const iosPlatform = "ios";\n'
                    "release.assets[iosPlatform] = {};\n\n"
                    "const siteURL = ",
                    1,
                ),
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_allows_historical_ios_references_outside_active_downloads(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            historical_ipa = "Mashangxie-1.15.0-iOS.ipa"
            release_notes_path = fixture_root / f".github/release-notes/v{self.version}.md"
            release_notes_path.write_text(
                release_notes_path.read_text(encoding="utf-8").replace(
                    "- 体验：",
                    f"- 体验：\n- 历史记录：`{historical_ipa}` 不是当前下载入口。",
                    1,
                ),
                encoding="utf-8",
            )
            refreshed = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(refreshed.returncode, 0, refreshed.stderr)
            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8")
                + f'\nconst historicalReleaseNote = "https://example.invalid/releases/{historical_ipa}";\n'
                + f'/* Historical CTA syntax: link.href = "{historical_ipa}" */\n',
                encoding="utf-8",
            )
            for relative_path in README_PATHS:
                readme = fixture_root / relative_path
                readme.write_text(
                    readme.read_text(encoding="utf-8")
                    + f"\nHistorical note: `{historical_ipa}` is not a current download.\n",
                    encoding="utf-8",
                )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_release_metadata_check_rejects_static_ios_href_assignment_after_release_config(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8")
                + "\nlet staleDownloadURL;\n"
                + f'staleDownloadURL = "{stale_download_url}";\n'
                'const staleDownloadLink = document.createElement("a");\n'
                'staleDownloadLink.href = staleDownloadURL;\n',
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_top_level_readme_ios_download_links(self) -> None:
        stale_download_url = (
            "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
            "Mashangxie-1.15.0-iOS.ipa"
        )
        for relative_path in README_PATHS:
            with self.subTest(relative_path=relative_path), tempfile.TemporaryDirectory() as temporary_directory:
                fixture_root = Path(temporary_directory)
                create_fixture(fixture_root)
                prepared = self.prepare(fixture_root, "macos,windows")
                self.assertEqual(prepared.returncode, 0, prepared.stderr)

                readme = fixture_root / relative_path
                readme.write_text(
                    readme.read_text(encoding="utf-8")
                    + f"\n[Download iOS IPA]({stale_download_url})\n",
                    encoding="utf-8",
                )
                checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

                self.assertNotEqual(checked.returncode, 0)
                self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_reference_style_readme_ios_download_links(self) -> None:
        stale_download_url = (
            "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
            "Mashangxie-1.15.0-iOS.ipa"
        )
        for relative_path in README_PATHS:
            with self.subTest(relative_path=relative_path), tempfile.TemporaryDirectory() as temporary_directory:
                fixture_root = Path(temporary_directory)
                create_fixture(fixture_root)
                prepared = self.prepare(fixture_root, "macos,windows")
                self.assertEqual(prepared.returncode, 0, prepared.stderr)

                readme = fixture_root / relative_path
                readme.write_text(
                    readme.read_text(encoding="utf-8")
                    + "\n[Download iOS IPA][legacy-ios-download]\n"
                    + f"[legacy-ios-download]: {stale_download_url}\n",
                    encoding="utf-8",
                )
                checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

                self.assertNotEqual(checked.returncode, 0)
                self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_shortcut_reference_readme_ios_download_links(self) -> None:
        stale_download_url = (
            "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
            "Mashangxie-1.15.0-iOS.ipa"
        )
        for relative_path in README_PATHS:
            with self.subTest(relative_path=relative_path), tempfile.TemporaryDirectory() as temporary_directory:
                fixture_root = Path(temporary_directory)
                create_fixture(fixture_root)
                prepared = self.prepare(fixture_root, "macos,windows")
                self.assertEqual(prepared.returncode, 0, prepared.stderr)

                readme = fixture_root / relative_path
                readme.write_text(
                    readme.read_text(encoding="utf-8")
                    + "\n[Download iOS IPA]\n"
                    + f"[Download iOS IPA]: {stale_download_url}\n",
                    encoding="utf-8",
                )
                checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

                self.assertNotEqual(checked.returncode, 0)
                self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_autolink_readme_ios_download_link(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            readme = fixture_root / "README.md"
            readme.write_text(
                readme.read_text(encoding="utf-8") + f"\n<{stale_download_url}>\n",
                encoding="utf-8",
            )
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_bare_readme_ios_download_url(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            readme = fixture_root / "README.md"
            readme.write_text(
                readme.read_text(encoding="utf-8") + f"\n{stale_download_url}\n",
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_unquoted_html_readme_ios_download_link(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            readme = fixture_root / "README.md"
            readme.write_text(
                readme.read_text(encoding="utf-8")
                + f"\n<a href={stale_download_url}>Download iOS IPA</a>\n",
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_allows_non_active_readme_ios_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            stale_download_url = (
                "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0/"
                "Mashangxie-1.15.0-iOS.ipa"
            )
            readme = fixture_root / "README.md"
            readme.write_text(
                readme.read_text(encoding="utf-8")
                + "\nHistorical release artifact Mashangxie-1.15.0-iOS.ipa is not a current download.\n"
                + f"\n`<{stale_download_url}>`\n"
                + "\n```markdown\n"
                + f"[Historical iOS IPA]({stale_download_url})\n"
                + f'<a href="{stale_download_url}">Historical iOS IPA</a>\n'
                + "```\n",
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_release_metadata_check_rejects_assembled_ios_artifact_references(self) -> None:
        assembled_url = (
            'const staleDownloadBase = "https://github.com/xingbofeng/VoxFlow/releases/download/v1.15.0";\n'
            'const staleAssetName = "Mashangxie-" + "1.15.0-iOS.ipa";\n'
        )

        for location, mutate_script in (
            (
                "releaseDownloadURLs.ios",
                lambda text: text.replace(
                    "const siteURL = ",
                    assembled_url
                    + "releaseDownloadURLs.ios = `${staleDownloadBase}/${staleAssetName}`;\n\n"
                    + "const siteURL = ",
                    1,
                ),
            ),
            (
                "anchor.href",
                lambda text: text
                + "\n"
                + assembled_url
                + 'const staleDownloadLink = document.createElement("a");\n'
                + "staleDownloadLink.href = `${staleDownloadBase}/${staleAssetName}`;\n",
            ),
            (
                "queried anchor.href",
                lambda text: text
                + "\n"
                + assembled_url
                + 'const staleDownloadLink = document.querySelector(".download-button");\n'
                + "if (staleDownloadLink) staleDownloadLink.href = `${staleDownloadBase}/${staleAssetName}`;\n",
            ),
            (
                "queried anchor list href",
                lambda text: text
                + "\n"
                + assembled_url
                + 'document.querySelectorAll(".download-button").forEach((link) => {\n'
                + "  link.href = `${staleDownloadBase}/${staleAssetName}`;\n"
                + "});\n",
            ),
            (
                "DOMContentLoaded anchor.href",
                lambda text: text
                + "\n"
                + assembled_url
                + 'document.addEventListener("DOMContentLoaded", () => {\n'
                + '  document.querySelector(".download-button").href = `${staleDownloadBase}/${staleAssetName}`;\n'
                + "});\n",
            ),
            (
                "load anchor.href",
                lambda text: text
                + "\n"
                + assembled_url
                + 'window.addEventListener("load", () => {\n'
                + '  document.querySelector(".download-button").href = `${staleDownloadBase}/${staleAssetName}`;\n'
                + "});\n",
            ),
        ):
            with self.subTest(location=location), tempfile.TemporaryDirectory() as temporary_directory:
                fixture_root = Path(temporary_directory)
                create_fixture(fixture_root)
                prepared = self.prepare(fixture_root, "macos,windows")
                self.assertEqual(prepared.returncode, 0, prepared.stderr)

                script = fixture_root / "docs/script.js"
                script.write_text(mutate_script(script.read_text(encoding="utf-8")), encoding="utf-8")
                checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

                self.assertNotEqual(checked.returncode, 0)
                self.assertIn("unselected iOS", checked.stderr)

    def test_release_metadata_check_rejects_fully_split_ios_artifact_assignment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory)
            create_fixture(fixture_root)
            prepared = self.prepare(fixture_root, "macos,windows")
            self.assertEqual(prepared.returncode, 0, prepared.stderr)

            script = fixture_root / "docs/script.js"
            script.write_text(
                script.read_text(encoding="utf-8").replace(
                    "const siteURL = ",
                    'const stalePrefix = "Masha" + "ngxie-";\n'
                    'const staleSuffix = "-i" + "OS.ipa";\n'
                    'releaseDownloadURLs.ios = `${stalePrefix}1.15.0${staleSuffix}`;\n\n'
                    "const siteURL = ",
                    1,
                ),
                encoding="utf-8",
            )

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)


if __name__ == "__main__":
    unittest.main()
