#!/usr/bin/env python3
"""Focused behavior checks for the declared release-platform contract."""

from __future__ import annotations

import importlib.util
import unittest
from copy import deepcopy
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parents[2]
PLATFORM_CONTRACT = ROOT / "scripts/release_platforms.py"


def load_release_platforms(test_case: unittest.TestCase) -> ModuleType:
    test_case.assertTrue(
        PLATFORM_CONTRACT.exists(),
        "scripts/release_platforms.py must provide the release platform contract",
    )
    spec = importlib.util.spec_from_file_location("release_platforms", PLATFORM_CONTRACT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def release_metadata(
    platforms: tuple[str, ...] = ("macos", "windows", "ios"),
) -> dict[str, object]:
    version = "1.16.0"
    tag = f"v{version}"
    base = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}"
    dmg = f"VoxFlow-{version}-macOS.dmg"
    installer = f"VoxFlow-{version}-windows-x64-setup.exe"
    portable = f"VoxFlow-{version}-windows-x64-portable.zip"
    ipa = f"Mashangxie-{version}-iOS.ipa"
    assets = {
        "macos": {"dmg": {"name": dmg, "downloadURL": f"{base}/{dmg}"}},
        "windows": {
            "installer": {"name": installer, "downloadURL": f"{base}/{installer}"},
            "portable": {"name": portable, "downloadURL": f"{base}/{portable}"},
        },
        "ios": {
            "ipa": {"name": ipa, "downloadURL": f"{base}/{ipa}"},
            "distribution": "ad-hoc",
        },
    }
    return {
        "version": version,
        "tag": tag,
        "assetName": dmg,
        "releasePageURL": f"https://github.com/xingbofeng/VoxFlow/releases/tag/{tag}",
        "downloadURL": f"{base}/{dmg}",
        "publishedPlatforms": list(platforms),
        "assets": {platform: assets[platform] for platform in platforms},
    }


class ReleasePlatformsTests(unittest.TestCase):
    def test_accepts_the_macos_and_windows_declaration(self) -> None:
        release_platforms = load_release_platforms(self)
        metadata = release_metadata(("macos", "windows"))

        self.assertEqual(
            release_platforms.parse_published_platforms(metadata["publishedPlatforms"]),
            ("macos", "windows"),
        )
        paths = release_platforms.release_metadata_paths(metadata)
        self.assertIn(("publishedPlatforms",), paths)
        self.assertNotIn(("assets", "ios", "ipa", "name"), paths)

    def test_accepts_the_three_platform_declaration(self) -> None:
        release_platforms = load_release_platforms(self)
        metadata = release_metadata()

        self.assertEqual(
            release_platforms.parse_published_platforms(metadata["publishedPlatforms"]),
            ("macos", "windows", "ios"),
        )
        self.assertIn(
            ("assets", "ios", "distribution"),
            release_platforms.release_metadata_paths(metadata),
        )

    def test_rejects_a_noncanonical_platform_order(self) -> None:
        release_platforms = load_release_platforms(self)

        with self.assertRaises(release_platforms.PlatformContractError):
            release_platforms.parse_published_platforms(["windows", "macos"])

    def test_rejects_an_unexpected_platform_asset(self) -> None:
        release_platforms = load_release_platforms(self)
        metadata = release_metadata(("macos", "windows"))
        full_assets = release_metadata()["assets"]
        assert isinstance(full_assets, dict)
        assets = metadata["assets"]
        assert isinstance(assets, dict)
        assets["ios"] = deepcopy(full_assets["ios"])

        with self.assertRaisesRegex(release_platforms.PlatformContractError, "assets\\.ios"):
            release_platforms.documented_asset_names(metadata)

    def test_derives_documented_asset_names_in_platform_and_kind_order(self) -> None:
        release_platforms = load_release_platforms(self)
        metadata = release_metadata()

        self.assertEqual(
            release_platforms.documented_asset_names(metadata),
            (
                "VoxFlow-1.16.0-macOS.dmg",
                "VoxFlow-1.16.0-windows-x64-setup.exe",
                "VoxFlow-1.16.0-windows-x64-portable.zip",
                "Mashangxie-1.16.0-iOS.ipa",
            ),
        )


if __name__ == "__main__":
    unittest.main()
