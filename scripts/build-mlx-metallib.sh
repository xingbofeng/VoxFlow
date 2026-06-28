#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-mlx-metallib.sh [debug|release] [--force]

Builds the MLX Metal shader library required by speech-swift's MLX backend.
Run swift build first so SwiftPM has fetched mlx-swift and created .build.

If xcrun reports a missing Metal Toolchain, run:
  xcodebuild -downloadComponent MetalToolchain
EOF
}

CONFIG="${1:-release}"
FORCE=0
if [[ "$CONFIG" == "--force" ]]; then
  FORCE=1
  CONFIG="${2:-release}"
elif [[ "${2:-}" == "--force" ]]; then
  FORCE=1
fi

if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  usage
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build}"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "error: $BUILD_DIR not found (run swift build first)" >&2
  exit 1
fi

OUT_DIR="$(find "$BUILD_DIR" -maxdepth 3 -type d -path "*-apple-macosx/$CONFIG" | head -n 1 || true)"
if [[ -z "${OUT_DIR:-}" || ! -d "$OUT_DIR" ]]; then
  OUT_DIR="$BUILD_DIR/$CONFIG"
fi
if [[ ! -d "$OUT_DIR" ]]; then
  OUT_DIR="$(find "$BUILD_DIR" -maxdepth 3 -type d -path "*/$CONFIG" | head -n 1 || true)"
fi
if [[ -z "${OUT_DIR:-}" || ! -d "$OUT_DIR" ]]; then
  echo "error: failed to locate SwiftPM output dir for config=$CONFIG under $BUILD_DIR" >&2
  exit 1
fi

MLX_SWIFT_DIR="$BUILD_DIR/checkouts/mlx-swift"
KERNELS_DIR="$MLX_SWIFT_DIR/Source/Cmlx/mlx/mlx/backend/metal/kernels"

if [[ -d "$MLX_SWIFT_DIR/.git" && ! -d "$KERNELS_DIR" ]]; then
  git -C "$MLX_SWIFT_DIR" submodule update --init --recursive Source/Cmlx/mlx
fi

if [[ ! -d "$KERNELS_DIR" ]]; then
  echo "error: MLX kernels dir not found at $KERNELS_DIR" >&2
  echo "hint: ensure dependencies are fetched with swift build" >&2
  exit 1
fi

METAL_SRCS=()
while IFS= read -r src; do
  METAL_SRCS+=("$src")
done < <(find "$KERNELS_DIR" -type f -name '*.metal' ! -name '*_nax.metal' | LC_ALL=C sort)

if [[ "${#METAL_SRCS[@]}" -eq 0 ]]; then
  echo "error: no .metal sources found under $KERNELS_DIR" >&2
  exit 1
fi

OUT_METALLIB="$OUT_DIR/mlx.metallib"
OUT_DEFAULT_METALLIB="$OUT_DIR/default.metallib"
HASH_FILE="$OUT_DIR/.mlx.metallib.sha"
CURRENT_HASH="$(find "$KERNELS_DIR" -type f \( -name '*.metal' -o -name '*.h' \) ! -name '*_nax.metal' | LC_ALL=C sort | xargs cat | shasum -a 256 | awk '{print $1}')"

if [[ "$FORCE" != "1" && -f "$OUT_METALLIB" && -f "$HASH_FILE" ]]; then
  PREV_HASH="$(cat "$HASH_FILE" 2>/dev/null || true)"
  if [[ "$CURRENT_HASH" == "$PREV_HASH" ]]; then
    cp "$OUT_METALLIB" "$OUT_DEFAULT_METALLIB"
    echo "mlx.metallib is up to date: $OUT_METALLIB"
    exit 0
  fi
fi

TMPDIR_ROOT="${TMPDIR:-/tmp}"
TMP="$(mktemp -d "$TMPDIR_ROOT/voxflow-mlx-metallib.XXXXXX")"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

AIR_FILES=()
METAL_FLAGS=(
  -x metal
  -Wall
  -Wextra
  -fno-fast-math
  -Wno-c++17-extensions
  -Wno-c++20-extensions
)

echo "Compiling ${#METAL_SRCS[@]} MLX Metal sources..."
for SRC in "${METAL_SRCS[@]}"; do
  REL="${SRC#"$KERNELS_DIR/"}"
  KEY="$(printf '%s' "$REL" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
  OUT_AIR="$TMP/$KEY.air"

  if ! xcrun -sdk macosx metal "${METAL_FLAGS[@]}" -c "$SRC" -I"$KERNELS_DIR" -I"$MLX_SWIFT_DIR/Source/Cmlx/mlx" -o "$OUT_AIR" 2>"$TMP/metal.err"; then
    if grep -q "missing Metal Toolchain" "$TMP/metal.err" 2>/dev/null; then
      echo "error: Xcode Metal Toolchain is missing." >&2
      echo "run: xcodebuild -downloadComponent MetalToolchain" >&2
    fi
    cat "$TMP/metal.err" >&2
    exit 1
  fi
  AIR_FILES+=("$OUT_AIR")
done

echo "Linking mlx.metallib -> $OUT_METALLIB"
xcrun -sdk macosx metallib "${AIR_FILES[@]}" -o "$OUT_METALLIB"
cp "$OUT_METALLIB" "$OUT_DEFAULT_METALLIB"
printf '%s' "$CURRENT_HASH" > "$HASH_FILE"
echo "OK: wrote $OUT_METALLIB and $OUT_DEFAULT_METALLIB"
