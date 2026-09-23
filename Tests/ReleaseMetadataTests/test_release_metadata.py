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


def javascript_release_download_state(path: Path) -> dict[str, object]:
    prelude, _, _ = path.read_text(encoding="utf-8").partition('const siteURL = ')
    node_program = """
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(0, "utf8");
const context = { process };
vm.runInNewContext(
  source + "\\nprocess.stdout.write(JSON.stringify({ urls: releaseDownloadURLs, iosURL: releaseDownloadURLForPlatform(\\\"ios\\\") }));",
  context,
);
"""
    completed = subprocess.run(
        ["node", "-e", node_program],
        input=prelude,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr)
    return json.loads(completed.stdout)


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


class ReleaseMetadataTests(unittest.TestCase):
    version = "9.8.7"
    build = "42"

    def prepare(
        self,
        fixture_root: Path,
        platforms: str | None = None,
        version: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        arguments = ("--version", version or self.version, "--build", self.build)
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
            self.assertNotIn(ios_ipa, release_notes)
            self.assertNotIn(ios_ipa, script.read_text(encoding="utf-8"))
            self.assertNotIn(ios_ipa, index.read_text(encoding="utf-8"))
            self.assertNotIn('data-download-platform="ios"', index.read_text(encoding="utf-8"))
            download_state = javascript_release_download_state(script)
            self.assertNotIn("ios", download_state["urls"])
            self.assertIsNone(download_state["iosURL"])
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
            self.assertIn(ios_ipa, script.read_text(encoding="utf-8"))
            self.assertIn(ios_ipa, index.read_text(encoding="utf-8"))
            self.assertIn('data-download-platform="ios"', index.read_text(encoding="utf-8"))
            download_state = javascript_release_download_state(script)
            self.assertEqual(
                download_state["iosURL"],
                f"https://github.com/xingbofeng/VoxFlow/releases/download/v{restored_version}/{ios_ipa}",
            )
            for relative_path in README_PATHS:
                self.assertIn(ios_ipa, (fixture_root / relative_path).read_text(encoding="utf-8"))

            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)
            self.assertEqual(checked.returncode, 0, checked.stderr)

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

            stale_ios_ipa = "Mashangxie-1.15.0-iOS.ipa"
            index = fixture_root / "docs/index.html"
            index.write_text(
                index.read_text(encoding="utf-8")
                + f'\n<a href="https://github.com/xingbofeng/VoxFlow/releases/download/v{self.version}/{stale_ios_ipa}">iOS</a>\n',
                encoding="utf-8",
            )
            checked = run_script(fixture_root, CHECK_RELEASE_METADATA)

            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("unselected iOS", checked.stderr)


if __name__ == "__main__":
    unittest.main()
