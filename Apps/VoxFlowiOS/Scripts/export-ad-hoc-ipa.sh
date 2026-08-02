#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 <archive> <export-dir> <final-ipa> <team-id> <app-profile> <keyboard-profile>" >&2
  exit 64
fi

archive_path="$1"
export_dir="$2"
final_ipa="$3"
team_id="$4"
app_profile="$5"
keyboard_profile="$6"

[[ -d "$archive_path" ]] || { echo "Archive not found: $archive_path" >&2; exit 1; }
for value in "$team_id" "$app_profile" "$keyboard_profile"; do
  [[ -n "$value" ]] || { echo "Ad Hoc export requires non-empty signing metadata" >&2; exit 2; }
done

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
export_options="$temporary_dir/ExportOptions.plist"

/usr/libexec/PlistBuddy -c 'Add :method string ad-hoc' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $team_id" "$export_options"
/usr/libexec/PlistBuddy -c 'Add :signingCertificate string Apple Distribution' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$export_options"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:com.mashangxie.ios string $app_profile" "$export_options"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:com.mashangxie.ios.keyboard string $keyboard_profile" "$export_options"

rm -rf "$export_dir/export"
mkdir -p "$export_dir/export" "$(dirname "$final_ipa")"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" xcrun xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_dir/export" \
  -exportOptionsPlist "$export_options"

exported_ipa="$(find "$export_dir/export" -maxdepth 1 -type f -name '*.ipa' | head -1)"
[[ -n "$exported_ipa" ]] || { echo "xcodebuild did not export an IPA" >&2; exit 1; }
mv "$exported_ipa" "$final_ipa"
