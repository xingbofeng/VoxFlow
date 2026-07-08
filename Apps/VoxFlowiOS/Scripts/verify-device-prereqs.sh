#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/VoxFlowiOS.xcodeproj"
DEVICE_UDID="${MASHANGXIE_DEVICE_UDID:-}"
TEAM_ID="${MASHANGXIE_DEVELOPMENT_TEAM:-}"
RUN_GENERIC_BUILD=1
RUN_DEVICE_BUILD=0

usage() {
  cat <<'EOF'
Usage:
  Apps/VoxFlowiOS/Scripts/verify-device-prereqs.sh [options]

Options:
  --no-build       Skip generic iOS build checks.
  --device-build   Also run a signed device build. Requires:
                   MASHANGXIE_DEVICE_UDID=<physical device udid>
                   MASHANGXIE_DEVELOPMENT_TEAM=<Apple team id>
  -h, --help       Show this help.

This script verifies preconditions for the manual Mashangxie iOS keyboard
acceptance flow. It does not replace physical-device WeChat validation.
EOF
}

while (($#)); do
  case "$1" in
    --no-build)
      RUN_GENERIC_BUILD=0
      ;;
    --device-build)
      RUN_DEVICE_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required but was not found in PATH." >&2
  exit 127
fi

echo "== Mashangxie iOS device validation preflight =="
echo "Project: $PROJECT"

python3 "$ROOT_DIR/Scripts/write-dev-cloud-resource.py" "$ROOT_DIR/Generated/DevCloudCredentials.plist"
xcodegen generate

if [[ "$RUN_GENERIC_BUILD" -eq 1 ]]; then
  echo
  echo "== Generic iOS build checks =="
  xcodebuild -quiet -project "$PROJECT" -scheme MashangxieKeyboard -destination 'generic/platform=iOS' build
  xcodebuild -quiet -project "$PROJECT" -scheme Mashangxie -destination 'generic/platform=iOS' build
fi

echo
echo "== Device inventory =="
DEVICE_LIST="$(xcrun xctrace list devices)"
printf '%s\n' "$DEVICE_LIST"

ONLINE_IOS_DEVICES="$(
  printf '%s\n' "$DEVICE_LIST" | awk '
    $0 == "== Devices ==" { section = "devices"; next }
    $0 ~ /^== / { section = ""; next }
    section == "devices" && $0 ~ /\([0-9]+\.[0-9]+/ && $0 !~ /Mac/ { print }
  '
)"

if [[ -z "$ONLINE_IOS_DEVICES" ]]; then
  cat <<'EOF'

No online physical iPhone/iPad is available to this Mac.
Manual acceptance remains blocked until a physical device is online and trusted.

Next manual validation checklist:
  1. Install Mashangxie with the embedded MashangxieKeyboard extension.
  2. Enable the keyboard in iOS Settings > General > Keyboard > Keyboards.
  3. Enable Full Access when provider/App Group behavior requires it.
  4. Open WeChat, focus a text field, and switch to Mashangxie.
  5. Validate warm-path voice input, cold-start mashangxie:// fallback,
     stop/cancel, final insertion, Chinese 26-key, Chinese 9-key/T9,
     mode switching, and voice after Rime composition.
EOF
  exit 2
fi

echo
echo "Online physical iOS device candidates:"
printf '%s\n' "$ONLINE_IOS_DEVICES"

if [[ "$RUN_DEVICE_BUILD" -eq 1 ]]; then
  if [[ -z "$DEVICE_UDID" || -z "$TEAM_ID" ]]; then
    cat <<'EOF' >&2

--device-build requires:
  MASHANGXIE_DEVICE_UDID=<physical device udid>
  MASHANGXIE_DEVELOPMENT_TEAM=<Apple team id>
EOF
    exit 64
  fi

  echo
  echo "== Signed physical-device build =="
  xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme Mashangxie \
    -destination "id=$DEVICE_UDID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    -allowProvisioningUpdates \
    build
fi

cat <<'EOF'

Preflight is ready for manual validation. Continue with the WeChat checklist in
Apps/VoxFlowiOS/NOTES.md section "1.13 Manual WeChat validation script".
EOF
