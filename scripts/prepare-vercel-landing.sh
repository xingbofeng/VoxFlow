#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
source_dir="$root/.build/vercel-landing"

"$root/scripts/build-landing-site.sh"

rm -rf "$source_dir"
mkdir -p "$source_dir/.vercel" "$source_dir/api" "$source_dir/public"

cp -R "$root/.build/landing-site/." "$source_dir/public/"
cp "$root/api/wechat-signature.js" "$source_dir/api/wechat-signature.js"
if [[ -n "${VERCEL_ORG_ID:-}" && -n "${VERCEL_PROJECT_ID:-}" ]]; then
  printf '{"orgId":"%s","projectId":"%s"}\n' "$VERCEL_ORG_ID" "$VERCEL_PROJECT_ID" > "$source_dir/.vercel/project.json"
elif [[ -f "$root/.vercel/project.json" ]]; then
  cp "$root/.vercel/project.json" "$source_dir/.vercel/project.json"
fi
cat > "$source_dir/vercel.json" <<'JSON'
{
  "cleanUrls": true,
  "trailingSlash": false,
  "rewrites": [
    {
      "source": "/((?!api/.*|assets/.*|release.json|releases-data.js|script.js|styles.css|MP_verify_1qnofqBMqq6muauP.txt).*)",
      "destination": "/"
    }
  ]
}
JSON

echo "prepared Vercel landing source at $source_dir"
