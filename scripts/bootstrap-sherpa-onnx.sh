#!/bin/bash
set -euo pipefail

VERSION="1.13.3"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
FRAMEWORK_DIR="$VENDOR_DIR/sherpa-onnx.xcframework"
LIB_DIR="$FRAMEWORK_DIR/macos-arm64_x86_64"
BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}"
XCFRAMEWORK_ARCHIVE="sherpa-onnx-v${VERSION}-macos-xcframework-static.tar.bz2"
RUNTIME_ARCHIVE="sherpa-onnx-v${VERSION}-osx-universal2-static-no-tts-lib.tar.bz2"
XCFRAMEWORK_SHA256="e1dcd71368ce7dba20622c75f8bdd1a2d2eda4265ce4a1be4a1ac3a2fc74dc9a"
RUNTIME_SHA256="5da99b3fd6cbfd5aecea36f36dc3702a7e3888b22aabbbe3634030511f767bff"

if [[ -f "$LIB_DIR/libsherpa-onnx.a" && -f "$LIB_DIR/libonnxruntime.a" ]]; then
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

download_and_verify() {
  local archive="$1"
  local expected_sha="$2"
  curl -fL --retry 3 "$BASE_URL/$archive" -o "$tmp_dir/$archive"
  local actual_sha
  actual_sha="$(shasum -a 256 "$tmp_dir/$archive" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "Checksum mismatch for $archive" >&2
    exit 1
  fi
}

echo "Preparing sherpa-onnx ${VERSION}..."
download_and_verify "$XCFRAMEWORK_ARCHIVE" "$XCFRAMEWORK_SHA256"
download_and_verify "$RUNTIME_ARCHIVE" "$RUNTIME_SHA256"

mkdir -p "$VENDOR_DIR"
rm -rf "$FRAMEWORK_DIR"
tar -xjf "$tmp_dir/$XCFRAMEWORK_ARCHIVE" -C "$tmp_dir"
xcframework_root="$tmp_dir/sherpa-onnx-v${VERSION}-macos-xcframework-static/sherpa-onnx.xcframework"
if [[ ! -d "$xcframework_root" ]]; then
  xcframework_root="$(find "$tmp_dir" -maxdepth 3 -type d -name sherpa-onnx.xcframework -print -quit)"
fi
if [[ -z "${xcframework_root:-}" || ! -d "$xcframework_root" ]]; then
  echo "sherpa-onnx.xcframework was not found in $XCFRAMEWORK_ARCHIVE" >&2
  exit 1
fi
cp -R "$xcframework_root" "$FRAMEWORK_DIR"

tar -xjf "$tmp_dir/$RUNTIME_ARCHIVE" -C "$tmp_dir"
runtime_root="$tmp_dir/sherpa-onnx-v${VERSION}-osx-universal2-static-no-tts-lib"
cp "$runtime_root/lib/libonnxruntime.a" "$LIB_DIR/libonnxruntime.a"

echo "sherpa-onnx runtime is ready."
