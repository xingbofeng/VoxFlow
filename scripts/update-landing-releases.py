#!/usr/bin/env python3
import json
import os
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/releases-data.js"
INDEX = ROOT / "docs/index.html"
API_URL = "https://api.github.com/repos/xingbofeng/VoxFlow/releases?per_page=3"


def github_token() -> str:
    for key in ("GITHUB_TOKEN", "GH_TOKEN"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    try:
        result = subprocess.run(
            ["gh", "auth", "token"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return ""
    return result.stdout.strip()


def main() -> int:
    token = github_token()
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "VoxFlow landing release sync",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(
        API_URL,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        releases = json.load(response)

    payload = [
        {
            "tag_name": item.get("tag_name", ""),
            "name": item.get("name") or item.get("tag_name", ""),
            "body": item.get("body") or "",
            "html_url": item.get("html_url", ""),
            "published_at": item.get("published_at", ""),
        }
        for item in releases[:3]
    ]

    release_json = json.dumps(payload, ensure_ascii=False, indent=2)
    OUTPUT.write_text(
        "window.VOXFLOW_RELEASES = "
        + release_json
        + ";\n",
        encoding="utf-8",
    )
    index = INDEX.read_text(encoding="utf-8")
    start_marker = '<script id="voxflow-release-data" type="application/json">'
    end_marker = "</script>"
    start = index.index(start_marker) + len(start_marker)
    end = index.index(end_marker, start)
    safe_json = release_json.replace("</", "<\\/")
    INDEX.write_text(index[:start] + "\n" + safe_json + "\n  " + index[end:], encoding="utf-8")
    print(f"updated landing release data with {len(payload)} releases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
