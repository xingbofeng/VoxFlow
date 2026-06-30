#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT/.build/release/VoxFlow.app}"
DSYM_PATH="${2:-$ROOT/.build/release/VoxFlow.app.dSYM}"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/VoxFlow"

for name in SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT; do
  if [[ -z "${!name:-}" ]]; then
    echo "error: $name is required for Sentry dSYM upload" >&2
    exit 2
  fi
done

if [[ ! -x "$APP_BINARY" ]]; then
  echo "error: app binary not found: $APP_BINARY" >&2
  exit 2
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "error: sentry-cli not found; install it before uploading dSYM files" >&2
  exit 2
fi

rm -rf "$DSYM_PATH"
dsymutil "$APP_BINARY" -o "$DSYM_PATH"
test -d "$DSYM_PATH"

sentry-cli debug-files upload \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  "$DSYM_PATH"
