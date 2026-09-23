"""Declared release-platform validation shared by publication and landing gates."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any


SUPPORTED_PLATFORM_SETS = (
    ("macos", "windows"),
    ("macos", "windows", "ios"),
)
ASSET_KINDS = {
    "macos": ("dmg",),
    "windows": ("installer", "portable"),
    "ios": ("ipa",),
}

_TOP_LEVEL_METADATA_PATHS = (
    ("version",),
    ("tag",),
    ("assetName",),
    ("releasePageURL",),
    ("downloadURL",),
    ("publishedPlatforms",),
)


class PlatformContractError(ValueError):
    """Raised when declared release platforms and their assets disagree."""


def parse_published_platforms(
    value: Any,
    *,
    location: str = "release.publishedPlatforms",
) -> tuple[str, ...]:
    """Return the one supported ordered release-platform declaration."""

    if not isinstance(value, list):
        raise PlatformContractError(f"{location} must be a list.")

    platforms = tuple(value)
    if platforms not in SUPPORTED_PLATFORM_SETS:
        supported = " or ".join(repr(list(item)) for item in SUPPORTED_PLATFORM_SETS)
        raise PlatformContractError(f"{location} must be exactly {supported}.")
    return platforms


def validate_release_assets(
    metadata: Mapping[str, Any],
    platforms: Sequence[str] | None = None,
    *,
    location: str = "release",
) -> tuple[str, ...]:
    """Validate asset objects against a declared or supplied platform contract."""

    if not isinstance(metadata, Mapping):
        raise PlatformContractError(f"{location} must be an object.")

    if platforms is None:
        selected_platforms = parse_published_platforms(
            metadata.get("publishedPlatforms"),
            location=f"{location}.publishedPlatforms",
        )
    else:
        selected_platforms = _validate_platform_sequence(platforms, location)

    assets = metadata.get("assets")
    if not isinstance(assets, Mapping):
        raise PlatformContractError(f"{location}.assets must be an object.")

    for platform in assets:
        if platform not in selected_platforms:
            raise PlatformContractError(f"unexpected assets.{platform} in {location}.")

    for platform in selected_platforms:
        platform_assets = assets.get(platform)
        if not isinstance(platform_assets, Mapping):
            raise PlatformContractError(f"{location}.assets.{platform} must be an object.")
        _validate_platform_assets(platform_assets, platform, location)

    return selected_platforms


def documented_asset_names(
    metadata: Mapping[str, Any],
    *,
    location: str = "release",
) -> tuple[str, ...]:
    """Return ordered, de-duplicated asset names selected by the declaration."""

    platforms = validate_release_assets(metadata, location=location)
    assets = metadata["assets"]
    assert isinstance(assets, Mapping)

    names: list[str] = []
    for platform in platforms:
        platform_assets = assets[platform]
        assert isinstance(platform_assets, Mapping)
        for kind in ASSET_KINDS[platform]:
            asset = platform_assets[kind]
            assert isinstance(asset, Mapping)
            names.append(_required_asset_name(asset.get("name"), platform, kind, location))
    return tuple(dict.fromkeys(names))


def release_metadata_paths(
    metadata: Mapping[str, Any],
    *,
    location: str = "release",
) -> tuple[tuple[str, ...], ...]:
    """Return the strict metadata leaf paths selected by the platform declaration."""

    platforms = validate_release_assets(metadata, location=location)
    paths = list(_TOP_LEVEL_METADATA_PATHS)
    for platform in platforms:
        for kind in ASSET_KINDS[platform]:
            paths.extend(
                (
                    ("assets", platform, kind, "name"),
                    ("assets", platform, kind, "downloadURL"),
                )
            )
        if platform == "ios":
            paths.append(("assets", "ios", "distribution"))
    return tuple(paths)


def _validate_platform_sequence(
    platforms: Sequence[str],
    location: str,
) -> tuple[str, ...]:
    selected_platforms = tuple(platforms)
    if selected_platforms not in SUPPORTED_PLATFORM_SETS:
        supported = " or ".join(repr(list(item)) for item in SUPPORTED_PLATFORM_SETS)
        raise PlatformContractError(f"{location} platform contract must be exactly {supported}.")
    return selected_platforms


def _validate_platform_assets(
    platform_assets: Mapping[str, Any],
    platform: str,
    location: str,
) -> None:
    allowed_keys = set(ASSET_KINDS[platform])
    if platform == "ios":
        allowed_keys.add("distribution")

    for key in platform_assets:
        if key not in allowed_keys:
            raise PlatformContractError(
                f"unexpected {location}.assets.{platform}.{key}."
            )

    for kind in ASSET_KINDS[platform]:
        asset = platform_assets.get(kind)
        if not isinstance(asset, Mapping):
            raise PlatformContractError(
                f"{location}.assets.{platform}.{kind} must be an object."
            )
        _required_asset_name(asset.get("name"), platform, kind, location)

    if platform == "ios" and platform_assets.get("distribution") != "ad-hoc":
        raise PlatformContractError(
            f"{location}.assets.ios.distribution must be exactly 'ad-hoc'."
        )


def _required_asset_name(
    value: Any,
    platform: str,
    kind: str,
    location: str,
) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlatformContractError(
            f"{location}.assets.{platform}.{kind}.name must be a non-empty string."
        )
    return value.strip()
