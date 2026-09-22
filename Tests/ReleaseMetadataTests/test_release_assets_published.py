#!/usr/bin/env python3
"""Behavior checks for the landing-release publication gate."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from urllib.error import HTTPError
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / "scripts/check-release-assets-published.py"
GATE_SPEC = importlib.util.spec_from_file_location("release_asset_gate", GATE)
assert GATE_SPEC is not None
assert GATE_SPEC.loader is not None
release_asset_gate = importlib.util.module_from_spec(GATE_SPEC)
GATE_SPEC.loader.exec_module(release_asset_gate)


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


def published_release(metadata: dict[str, object]) -> dict[str, object]:
    assets = metadata["assets"]
    assert isinstance(assets, dict)
    return {
        "draft": False,
        "assets": [
            {"name": assets["macos"]["dmg"]["name"], "state": "uploaded"},
            {"name": assets["windows"]["installer"]["name"], "state": "uploaded"},
            {"name": assets["windows"]["portable"]["name"], "state": "uploaded"},
            {"name": assets["ios"]["ipa"]["name"], "state": "uploaded"},
        ],
    }


class ReleaseAssetsPublishedTests(unittest.TestCase):
    def run_gate(
        self,
        metadata: dict[str, object],
        release: dict[str, object],
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            metadata_path = temporary_path / "release.json"
            release_path = temporary_path / "github-release.json"
            output_path = temporary_path / "github-output"
            metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
            release_path.write_text(json.dumps(release), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(GATE),
                    "--metadata",
                    str(metadata_path),
                    "--release-json",
                    str(release_path),
                    "--github-output",
                    str(output_path),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            output = output_path.read_text(encoding="utf-8") if output_path.exists() else ""
            return completed, output

    def test_gate_allows_only_a_complete_uploaded_three_platform_release(self) -> None:
        metadata = release_metadata()
        completed, output = self.run_gate(metadata, published_release(metadata))

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(output, "ready=true\n")

    def test_gate_skips_a_release_missing_a_documented_platform_asset(self) -> None:
        metadata = release_metadata()
        release = published_release(metadata)
        release["assets"] = release["assets"][:-1]
        completed, output = self.run_gate(metadata, release)

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(output, "ready=false\n")
        self.assertIn("not published", completed.stdout)

    def test_gate_skips_a_draft_release(self) -> None:
        metadata = release_metadata()
        release = published_release(metadata)
        release["draft"] = True
        completed, output = self.run_gate(metadata, release)

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(output, "ready=false\n")
        self.assertIn("draft", completed.stdout)

    def test_gate_skips_an_asset_that_is_not_uploaded(self) -> None:
        metadata = release_metadata()
        release = published_release(metadata)
        release["assets"][2]["state"] = "starter"
        completed, output = self.run_gate(metadata, release)

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(output, "ready=false\n")
        self.assertIn("not published", completed.stdout)

    def test_gate_treats_a_missing_github_release_as_not_ready(self) -> None:
        not_found = HTTPError(
            "https://api.github.com/repos/xingbofeng/VoxFlow/releases/tags/v1.16.0",
            404,
            "Not Found",
            None,
            None,
        )
        with patch.object(
            release_asset_gate.urllib.request,
            "urlopen",
            side_effect=not_found,
        ):
            self.assertIsNone(
                release_asset_gate.fetch_release(
                    "xingbofeng/VoxFlow",
                    "v1.16.0",
                    "",
                )
            )

    def test_gate_fails_for_an_unexpected_github_api_error(self) -> None:
        forbidden = HTTPError(
            "https://api.github.com/repos/xingbofeng/VoxFlow/releases/tags/v1.16.0",
            403,
            "Forbidden",
            None,
            None,
        )
        with patch.object(
            release_asset_gate.urllib.request,
            "urlopen",
            side_effect=forbidden,
        ):
            with self.assertRaises(release_asset_gate.GateError):
                release_asset_gate.fetch_release(
                    "xingbofeng/VoxFlow",
                    "v1.16.0",
                    "",
                )

    def test_gate_rejects_malformed_multi_platform_metadata(self) -> None:
        metadata = release_metadata()
        assets = metadata["assets"]
        assert isinstance(assets, dict)
        del assets["ios"]
        completed, output = self.run_gate(metadata, published_release(release_metadata()))

        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(output, "")
        self.assertIn("release.assets.ios", completed.stderr)


if __name__ == "__main__":
    unittest.main()
