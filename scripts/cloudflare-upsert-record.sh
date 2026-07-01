#!/usr/bin/env bash
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ZONE_ID:?set CLOUDFLARE_ZONE_ID}"
: "${CF_RECORD_NAME:?set CF_RECORD_NAME}"
: "${CF_RECORD_TYPE:?set CF_RECORD_TYPE}"
: "${CF_RECORD_CONTENT:?set CF_RECORD_CONTENT}"

proxied=${CF_RECORD_PROXIED:-false}
ttl=${CF_RECORD_TTL:-1}
api="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"

existing_id=$(
  curl -fsS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${api}?type=${CF_RECORD_TYPE}&name=${CF_RECORD_NAME}" |
    jq -r '.result[0].id // empty'
)

payload=$(
  jq -n \
    --arg type "$CF_RECORD_TYPE" \
    --arg name "$CF_RECORD_NAME" \
    --arg content "$CF_RECORD_CONTENT" \
    --argjson proxied "$proxied" \
    --argjson ttl "$ttl" \
    '{type:$type,name:$name,content:$content,proxied:$proxied,ttl:$ttl}'
)

if [[ -n "$existing_id" ]]; then
  curl -fsS -X PUT "${api}/${existing_id}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload" >/dev/null
  echo "updated ${CF_RECORD_NAME}"
else
  curl -fsS -X POST "$api" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload" >/dev/null
  echo "created ${CF_RECORD_NAME}"
fi
