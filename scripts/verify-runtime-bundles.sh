#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <swiftpm-bin-dir> <app-bundle>" >&2
  exit 2
fi

bin_dir="$1"
app_bundle="$2"
resources_dir="$app_bundle/Contents/Resources"
missing=0

if [ ! -d "$bin_dir" ]; then
  echo "SwiftPM binary directory not found: $bin_dir" >&2
  exit 1
fi

if [ ! -d "$resources_dir" ]; then
  echo "App resources directory not found: $resources_dir" >&2
  exit 1
fi

for bundle in "$bin_dir"/*.bundle; do
  [ -d "$bundle" ] || continue
  bundle_name="$(basename "$bundle")"
  case "$bundle_name" in
    *Tests.bundle) continue ;;
  esac

  if [ ! -d "$resources_dir/$bundle_name" ]; then
    echo "Missing runtime resource bundle: $bundle_name" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi
