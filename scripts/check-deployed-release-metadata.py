#!/usr/bin/env python3
"""Ensure a deployed landing release document exposes every published platform download."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from release_platforms import (
    PlatformContractError,
    parse_published_platforms,
    release_metadata_paths,
    validate_release_assets,
)

MISSING = object()


class MetadataError(Exception):
    """Raised when release metadata is malformed or does not match the expected release."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare deployed landing release metadata with the checked-in release metadata."
    )
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--actual", type=Path, required=True)
    return parser.parse_args()


def load_metadata(path: Path) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MetadataError(f"could not read {path}: {error}") from error
    if not isinstance(decoded, dict):
        raise MetadataError(f"{path} must contain a JSON object")
    return decoded


def value_at(metadata: dict[str, Any], path: tuple[str, ...]) -> Any:
    value: Any = metadata
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return MISSING
        value = value[key]
    return value


def mismatches(expected: dict[str, Any], actual: dict[str, Any]) -> list[str]:
    try:
        expected_platforms = parse_published_platforms(
            expected.get("publishedPlatforms"),
            location="expected metadata.publishedPlatforms",
        )
        required_fields = release_metadata_paths(
            expected,
            location="expected metadata",
        )
    except PlatformContractError as error:
        raise MetadataError(str(error)) from error

    differences: list[str] = []
    for path in required_fields:
        expected_value = value_at(expected, path)
        field = ".".join(path)
        if expected_value is MISSING:
            raise MetadataError(f"expected metadata is missing {field}")

        actual_value = value_at(actual, path)
        if actual_value is MISSING:
            differences.append(f"missing {field}")
        elif actual_value != expected_value:
            differences.append(
                f"{field} mismatch: expected {expected_value!r}, got {actual_value!r}"
            )

    try:
        actual_platforms = parse_published_platforms(
            actual.get("publishedPlatforms"),
            location="actual metadata.publishedPlatforms",
        )
        validate_release_assets(
            actual,
            actual_platforms,
            location="actual metadata",
        )
    except PlatformContractError as error:
        differences.append(str(error))

    try:
        validate_release_assets(
            actual,
            expected_platforms,
            location="actual metadata",
        )
    except PlatformContractError as error:
        if str(error) not in differences:
            differences.append(str(error))
    return differences


def platform_download_summary(platforms: tuple[str, ...]) -> str:
    names = {"macos": "macOS", "windows": "Windows", "ios": "iOS"}
    labels = [names[platform] for platform in platforms]
    if len(labels) == 2:
        return " and ".join(labels)
    return ", ".join(labels[:-1]) + f", and {labels[-1]}"


def main() -> int:
    arguments = parse_arguments()
    try:
        expected = load_metadata(arguments.expected)
        actual = load_metadata(arguments.actual)
        differences = mismatches(expected, actual)
    except MetadataError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    if differences:
        print("::error::deployed release metadata is not current:", file=sys.stderr)
        for difference in differences:
            print(f"  - {difference}", file=sys.stderr)
        return 1

    platforms = parse_published_platforms(expected["publishedPlatforms"])
    print(
        f"Release metadata matches {expected['version']} with all "
        f"{platform_download_summary(platforms)} downloads."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
