#!/usr/bin/env python3
"""Verify that every documented platform download is published on GitHub."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_PATHS = (
    ("macos", "dmg"),
    ("windows", "installer"),
    ("windows", "portable"),
    ("ios", "ipa"),
)


class GateError(RuntimeError):
    """An invalid local contract or an unusable GitHub API response."""


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateError(f"Unable to read JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise GateError(f"{path} must contain a JSON object.")
    return value


def required_string(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise GateError(f"{location} must be a non-empty string.")
    return value.strip()


def documented_release_assets(metadata: dict[str, Any]) -> tuple[str, tuple[str, ...]]:
    tag = required_string(metadata.get("tag"), "release.tag")
    top_level_asset = required_string(metadata.get("assetName"), "release.assetName")
    assets = metadata.get("assets")
    if not isinstance(assets, dict):
        raise GateError("release.assets must be an object.")

    names: list[str] = []
    for platform, kind in ASSET_PATHS:
        platform_assets = assets.get(platform)
        if not isinstance(platform_assets, dict):
            raise GateError(f"release.assets.{platform} must be an object.")
        asset = platform_assets.get(kind)
        if not isinstance(asset, dict):
            raise GateError(f"release.assets.{platform}.{kind} must be an object.")
        names.append(
            required_string(
                asset.get("name"),
                f"release.assets.{platform}.{kind}.name",
            )
        )

    macos_dmg = names[0]
    if top_level_asset != macos_dmg:
        raise GateError("release.assetName must match release.assets.macos.dmg.name.")

    return tag, tuple(dict.fromkeys(names))


def fetch_release(repository: str, tag: str, token: str) -> dict[str, Any] | None:
    if repository.count("/") != 1 or any(not part for part in repository.split("/")):
        raise GateError("GITHUB_REPOSITORY must be in owner/repository form.")

    endpoint = (
        "https://api.github.com/repos/"
        f"{urllib.parse.quote(repository, safe='/')}/releases/tags/"
        f"{urllib.parse.quote(tag, safe='')}"
    )
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "VoxFlow release asset gate",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    try:
        with urllib.request.urlopen(
            urllib.request.Request(endpoint, headers=headers),
            timeout=20,
        ) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise GateError(
            f"GitHub Release API returned HTTP {error.code} while reading {tag}."
        ) from error
    except urllib.error.URLError as error:
        raise GateError(f"GitHub Release API is unavailable while reading {tag}: {error}.") from error
    except json.JSONDecodeError as error:
        raise GateError(f"GitHub Release API returned invalid JSON for {tag}.") from error

    if not isinstance(payload, dict):
        raise GateError(f"GitHub Release API returned an invalid response for {tag}.")
    return payload


def release_is_ready(release: dict[str, Any], expected_assets: tuple[str, ...]) -> tuple[bool, str]:
    if release.get("draft") is True:
        return False, "The documented GitHub Release is still a draft."

    release_assets = release.get("assets")
    if not isinstance(release_assets, list):
        raise GateError("GitHub Release response must contain an assets array.")

    uploaded = {
        item.get("name")
        for item in release_assets
        if isinstance(item, dict)
        and item.get("state") == "uploaded"
        and isinstance(item.get("name"), str)
    }
    missing = [name for name in expected_assets if name not in uploaded]
    if missing:
        return False, "Documented release assets are not published: " + ", ".join(missing)
    return True, "Every documented platform asset is published."


def write_output(path: Path | None, ready: bool) -> None:
    if path is not None:
        with path.open("a", encoding="utf-8") as output:
            output.write(f"ready={'true' if ready else 'false'}\n")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check whether docs/release.json points only to published GitHub assets."
    )
    parser.add_argument(
        "--metadata",
        type=Path,
        default=ROOT / "docs/release.json",
        help="release metadata to validate",
    )
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY", ""),
        help="GitHub owner/repository; defaults to GITHUB_REPOSITORY",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN", ""),
        help="GitHub token; defaults to GITHUB_TOKEN or GH_TOKEN",
    )
    parser.add_argument(
        "--release-json",
        type=Path,
        help="read a saved GitHub Release API response instead of calling the network",
    )
    parser.add_argument(
        "--github-output",
        type=Path,
        default=Path(os.environ["GITHUB_OUTPUT"]) if os.environ.get("GITHUB_OUTPUT") else None,
        help="optional GitHub Actions output file to receive ready=true or ready=false",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        metadata = load_json(arguments.metadata)
        tag, expected_assets = documented_release_assets(metadata)
        release = (
            load_json(arguments.release_json)
            if arguments.release_json is not None
            else fetch_release(arguments.repo, tag, arguments.token)
        )
        if release is None:
            write_output(arguments.github_output, False)
            print(f"::notice::GitHub Release {tag} is not published yet.")
            return 0

        ready, message = release_is_ready(release, expected_assets)
        write_output(arguments.github_output, ready)
        print(f"::notice::{message}")
        return 0
    except GateError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
