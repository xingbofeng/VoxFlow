#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/../.." && pwd)"

RIME_ICE_REPO="${RIME_ICE_REPO:-https://github.com/iDvel/rime-ice.git}"
RIME_ICE_REVISION="${RIME_ICE_REVISION:-846e5fcae56f0e3f4dcd8570319ffaf377e15471}"
BOOTSTRAP_VERSION="2"
SCHEMAS_DIR="$IOS_ROOT/ChineseInput/Resources/Schemas"
CACHE_ROOT="$REPO_ROOT/.build/ios-rime-ice"
CACHE_DIR="$CACHE_ROOT/rime-ice-$RIME_ICE_REVISION"
STAMP_FILE="$SCHEMAS_DIR/.rime-ice-revision"
STAMP_VALUE="$RIME_ICE_REVISION:$BOOTSTRAP_VERSION"

if [[ -f "$STAMP_FILE" ]] && [[ "$(cat "$STAMP_FILE")" == "$STAMP_VALUE" ]]; then
  echo "Rime Ice schemas ready: $RIME_ICE_REVISION"
  exit 0
fi

mkdir -p "$CACHE_ROOT"

if [[ ! -d "$CACHE_DIR/.git" ]]; then
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
  git -C "$CACHE_DIR" init --quiet
  git -C "$CACHE_DIR" remote add origin "$RIME_ICE_REPO"
  git -C "$CACHE_DIR" fetch --quiet --depth 1 origin "$RIME_ICE_REVISION"
  git -C "$CACHE_DIR" checkout --quiet --detach FETCH_HEAD
fi

rm -rf "$SCHEMAS_DIR"
mkdir -p "$SCHEMAS_DIR"

rsync -a --delete \
  --exclude '.git/' \
  --exclude '.github/' \
  --exclude '.gitignore' \
  --exclude 'AGENTS.md' \
  --exclude 'LICENSE' \
  --exclude 'README.md' \
  --exclude 'build/' \
  --exclude 'others/' \
  "$CACHE_DIR/" "$SCHEMAS_DIR/"

printf '%s' "$STAMP_VALUE" > "$STAMP_FILE"
echo "Rime Ice schemas bootstrapped: $RIME_ICE_REVISION"
