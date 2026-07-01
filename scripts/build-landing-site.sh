#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/.build/landing-site"

python3 "$root/scripts/update-landing-releases.py"

rm -rf "$out"
mkdir -p "$out/assets"
mkdir -p "$out/assets/optimized"

cp "$root/docs/index.html" "$out/"
cp "$root/docs/styles.css" "$out/"
cp "$root/docs/script.js" "$out/"
cp "$root/docs/release.json" "$out/"
cp "$root/docs/releases-data.js" "$out/"
cp "$root/docs/MP_verify_1qnofqBMqq6muauP.txt" "$out/"
cp "$root/docs/ready" "$out/"

cp "$root/docs/assets/wechat-share-logo.jpg" "$out/assets/"
cp "$root/docs/assets/optimized/"* "$out/assets/optimized/"

echo "built landing site at $out"
