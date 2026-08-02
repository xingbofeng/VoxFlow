#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  cat >&2 <<'EOF'
Usage:
  Apps/VoxFlowiOS/Scripts/verify-ios-ipa-contract.sh <ipa-path> [ios-root] [--signed]

Verifies the IPA contains the real app plus Mashangxie keyboard extension.
With --signed, also requires distribution signatures, embedded profiles, and
the App Group entitlement on both targets.
EOF
  exit 64
fi

IPA_PATH="$1"
IOS_ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SIGNING_MODE="${3:-}"
APP_GROUP_ID="group.com.mashangxie.ios"

[[ -z "$SIGNING_MODE" || "$SIGNING_MODE" == "--signed" ]] || {
  echo "Unknown verification mode: $SIGNING_MODE" >&2
  exit 64
}

fail() {
  echo "❌ $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print $2" "$1" 2>/dev/null
}

[[ -f "$IPA_PATH" ]] || fail "IPA not found: $IPA_PATH"
[[ -f "$IOS_ROOT/VoxFlowiOS/Mashangxie.entitlements" ]] || fail "Missing app entitlements"
[[ -f "$IOS_ROOT/Keyboard/Keyboard.entitlements" ]] || fail "Missing keyboard entitlements"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -q "$IPA_PATH" -d "$TMP_DIR"

APP_PATH="$(find "$TMP_DIR/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"
[[ -n "$APP_PATH" ]] || fail "Missing Payload/*.app"
[[ "$(basename "$APP_PATH")" == "Mashangxie.app" ]] || fail "Expected Mashangxie.app, got $(basename "$APP_PATH")"

KEYBOARD_PATH="$APP_PATH/PlugIns/MashangxieKeyboard.appex"
[[ -d "$KEYBOARD_PATH" ]] || fail "Missing embedded MashangxieKeyboard.appex"

APP_BUNDLE_ID="$(plist_value "$APP_PATH/Info.plist" ":CFBundleIdentifier")"
KEYBOARD_BUNDLE_ID="$(plist_value "$KEYBOARD_PATH/Info.plist" ":CFBundleIdentifier")"
EXTENSION_POINT="$(plist_value "$KEYBOARD_PATH/Info.plist" ":NSExtension:NSExtensionPointIdentifier")"

[[ "$APP_BUNDLE_ID" == "com.mashangxie.ios" ]] || fail "Unexpected app bundle id: $APP_BUNDLE_ID"
[[ "$KEYBOARD_BUNDLE_ID" == "com.mashangxie.ios.keyboard" ]] || fail "Unexpected keyboard bundle id: $KEYBOARD_BUNDLE_ID"
[[ "$EXTENSION_POINT" == "com.apple.keyboard-service" ]] || fail "Unexpected extension point: $EXTENSION_POINT"

[[ -f "$KEYBOARD_PATH/Frameworks/ChineseInput.framework/ChineseInput" ]] || fail "Missing ChineseInput.framework in appex"
[[ -f "$KEYBOARD_PATH/Frameworks/RimeKitObjC.framework/RimeKitObjC" ]] || fail "Missing RimeKitObjC.framework in appex"
[[ -f "$APP_PATH/Frameworks/ChineseInput.framework/ChineseInput" ]] || fail "Missing ChineseInput.framework in containing app"
[[ -f "$APP_PATH/Frameworks/RimeKitObjC.framework/RimeKitObjC" ]] || fail "Missing RimeKitObjC.framework in containing app"
[[ -f "$KEYBOARD_PATH/Frameworks/ChineseInput.framework/Schemas/build/rime_ice.table.bin" ]] \
  || fail "Missing prebuilt Rime Ice table in keyboard ChineseInput.framework"
[[ -f "$KEYBOARD_PATH/Frameworks/ChineseInput.framework/Schemas/build/t9.prism.bin" ]] \
  || fail "Missing prebuilt T9 prism in keyboard ChineseInput.framework"
[[ -f "$APP_PATH/Frameworks/ChineseInput.framework/Schemas/build/rime_ice.table.bin" ]] \
  || fail "Missing prebuilt Rime Ice table in app ChineseInput.framework"

if command -v otool >/dev/null 2>&1; then
  otool -l "$KEYBOARD_PATH/MashangxieKeyboard" | grep -q '@executable_path/Frameworks' \
    || fail "Keyboard executable missing appex Frameworks rpath"
  otool -l "$KEYBOARD_PATH/MashangxieKeyboard" | grep -q '@executable_path/../../Frameworks' \
    || fail "Keyboard executable missing containing app Frameworks rpath"
fi

APP_GROUPS_APP="$(plist_value "$IOS_ROOT/VoxFlowiOS/Mashangxie.entitlements" ":com.apple.security.application-groups:0")"
APP_GROUPS_KEYBOARD="$(plist_value "$IOS_ROOT/Keyboard/Keyboard.entitlements" ":com.apple.security.application-groups:0")"
[[ "$APP_GROUPS_APP" == "$APP_GROUP_ID" ]] || fail "App entitlement does not declare $APP_GROUP_ID"
[[ "$APP_GROUPS_KEYBOARD" == "$APP_GROUP_ID" ]] || fail "Keyboard entitlement does not declare $APP_GROUP_ID"

if [[ "$SIGNING_MODE" == "--signed" ]]; then
  [[ -f "$APP_PATH/embedded.mobileprovision" ]] || fail "Missing app provisioning profile"
  [[ -f "$KEYBOARD_PATH/embedded.mobileprovision" ]] || fail "Missing keyboard provisioning profile"
  [[ -f "$APP_PATH/_CodeSignature/CodeResources" ]] || fail "Missing app code signature"
  [[ -f "$KEYBOARD_PATH/_CodeSignature/CodeResources" ]] || fail "Missing keyboard code signature"
  codesign --verify --deep --strict "$APP_PATH" || fail "App signature verification failed"

  APP_SIGNED_ENTITLEMENTS="$TMP_DIR/app-entitlements.plist"
  KEYBOARD_SIGNED_ENTITLEMENTS="$TMP_DIR/keyboard-entitlements.plist"
  codesign -d --entitlements "$APP_SIGNED_ENTITLEMENTS" "$APP_PATH" >/dev/null 2>&1 \
    || fail "Unable to read app signed entitlements"
  codesign -d --entitlements "$KEYBOARD_SIGNED_ENTITLEMENTS" "$KEYBOARD_PATH" >/dev/null 2>&1 \
    || fail "Unable to read keyboard signed entitlements"
  [[ "$(plist_value "$APP_SIGNED_ENTITLEMENTS" ':com.apple.security.application-groups:0')" == "$APP_GROUP_ID" ]] \
    || fail "Signed app is missing $APP_GROUP_ID"
  [[ "$(plist_value "$KEYBOARD_SIGNED_ENTITLEMENTS" ':com.apple.security.application-groups:0')" == "$APP_GROUP_ID" ]] \
    || fail "Signed keyboard is missing $APP_GROUP_ID"
fi

echo "✅ IPA contract OK: $(basename "$IPA_PATH")"
echo "   App:      $APP_BUNDLE_ID"
echo "   Keyboard: $KEYBOARD_BUNDLE_ID"
echo "   AppGroup: $APP_GROUP_ID (source entitlements; runtime must be validated on device)"
[[ "$SIGNING_MODE" != "--signed" ]] || echo "   Signing:  Ad Hoc profiles and signatures verified"
