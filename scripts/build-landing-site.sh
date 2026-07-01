#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/.build/landing-site"

python3 "$root/scripts/update-landing-releases.py"

rm -rf "$out"
mkdir -p "$out/assets"

cp "$root/docs/index.html" "$out/"
cp "$root/docs/styles.css" "$out/"
cp "$root/docs/script.js" "$out/"
cp "$root/docs/release.json" "$out/"
cp "$root/docs/releases-data.js" "$out/"
cp "$root/docs/MP_verify_1qnofqBMqq6muauP.txt" "$out/"

cp "$root/docs/assets/voiceinput-logo.png" "$out/assets/"
cp "$root/docs/assets/voxflow-hero-workbench-promo-en.png" "$out/assets/"
cp "$root/docs/assets/voxflow-hero-workbench-promo-zh.png" "$out/assets/"

echo "built landing site at $out"
