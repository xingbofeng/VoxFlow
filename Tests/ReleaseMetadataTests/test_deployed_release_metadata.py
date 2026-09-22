#!/usr/bin/env python3
"""Behavior checks for deployed landing release metadata verification."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / "scripts/check-deployed-release-metadata.py"


def release_metadata() -> dict[str, object]:
    version = "1.16.0"
    tag = f"v{version}"
    base = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}"
    dmg = f"VoxFlow-{version}-macOS.dmg"
    installer = f"VoxFlow-{version}-windows-x64-setup.exe"
    portable = f"VoxFlow-{version}-windows-x64-portable.zip"
    ipa = f"Mashangxie-{version}-iOS.ipa"
    return {
        "version": version,
        "tag": tag,
        "assetName": dmg,
        "releasePageURL": f"https://github.com/xingbofeng/VoxFlow/releases/tag/{tag}",
        "downloadURL": f"{base}/{dmg}",
        "assets": {
            "macos": {"dmg": {"name": dmg, "downloadURL": f"{base}/{dmg}"}},
            "windows": {
                "installer": {"name": installer, "downloadURL": f"{base}/{installer}"},
                "portable": {"name": portable, "downloadURL": f"{base}/{portable}"},
            },
            "ios": {
                "ipa": {"name": ipa, "downloadURL": f"{base}/{ipa}"},
                "distribution": "ad-hoc",
            },
        },
    }


class DeployedReleaseMetadataTests(unittest.TestCase):
    def run_gate(
        self,
        expected: dict[str, object],
        actual: dict[str, object],
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            expected_path = temporary_path / "expected.json"
            actual_path = temporary_path / "actual.json"
            expected_path.write_text(json.dumps(expected), encoding="utf-8")
            actual_path.write_text(json.dumps(actual), encoding="utf-8")

            return subprocess.run(
                [
                    sys.executable,
                    str(GATE),
                    "--expected",
                    str(expected_path),
                    "--actual",
                    str(actual_path),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )

    def test_gate_accepts_matching_three_platform_metadata(self) -> None:
        expected = release_metadata()

        completed = self.run_gate(expected, deepcopy(expected))

        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_gate_rejects_legacy_metadata_missing_platform_assets(self) -> None:
        expected = release_metadata()
        actual = {
            "version": expected["version"],
            "downloadURL": expected["downloadURL"],
        }

        completed = self.run_gate(expected, actual)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("assets", completed.stderr)

    def test_gate_rejects_a_missing_windows_download(self) -> None:
        expected = release_metadata()
        actual = deepcopy(expected)
        assets = actual["assets"]
        assert isinstance(assets, dict)
        windows = assets["windows"]
        assert isinstance(windows, dict)
        windows.pop("portable")

        completed = self.run_gate(expected, actual)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("assets", completed.stderr)

    def test_gate_rejects_each_documented_platform_download_change(self) -> None:
        expected = release_metadata()
        fields = (
            ("assets", "macos", "dmg", "name"),
            ("assets", "macos", "dmg", "downloadURL"),
            ("assets", "windows", "installer", "name"),
            ("assets", "windows", "installer", "downloadURL"),
            ("assets", "windows", "portable", "name"),
            ("assets", "windows", "portable", "downloadURL"),
            ("assets", "ios", "ipa", "name"),
            ("assets", "ios", "ipa", "downloadURL"),
            ("assets", "ios", "distribution"),
        )

        for path in fields:
            with self.subTest(path=path):
                actual = deepcopy(expected)
                value = actual
                for key in path[:-1]:
                    assert isinstance(value, dict)
                    value = value[key]
                assert isinstance(value, dict)
                value[path[-1]] = "unexpected"

                completed = self.run_gate(expected, actual)

                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(".".join(path), completed.stderr)

    def test_gate_rejects_a_different_primary_download(self) -> None:
        expected = release_metadata()
        actual = deepcopy(expected)
        actual["downloadURL"] = "https://example.invalid/VoxFlow.dmg"

        completed = self.run_gate(expected, actual)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("downloadURL", completed.stderr)


if __name__ == "__main__":
    unittest.main()
