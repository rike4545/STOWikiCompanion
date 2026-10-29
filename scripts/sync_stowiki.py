#!/usr/bin/env python3
"""Refresh STO Wiki metadata indexes. Does not download page bodies or binary assets."""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API_URL = os.environ.get("STOWIKI_API_URL", "https://stowiki.net/api.php")
USER_AGENT = "STOWikiCompanionMetadataSync/1.0 (GitHub Actions; read-only; source: https://github.com/rike4545/STOWikiCompanion)"
OUT = Path("data")
MAX_ASSETS = int(os.environ.get("STOWIKI_MAX_ASSETS", "10000"))


def api_get(params):
    url = API_URL + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    last_error = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=35) as response:
                if response.status != 200:
                    raise RuntimeError("API returned HTTP " + str(response.status))
                payload = json.loads(response.read().decode("utf-8"))
                if "error" in payload:
                    raise RuntimeError("MediaWiki API error: " + str(payload["error"]))
                return payload
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as exc:
            last_error = exc
            if attempt < 3:
                time.sleep(2 ** attempt)
    raise RuntimeError("Could not query API: " + str(last_error))


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + chr(10), encoding="utf-8")


def sync_recent_changes():
    payload = api_get({
        "action": "query", "list": "recentchanges",
        "rcprop": "title|timestamp|ids|sizes|flags|comment",
        "rclimit": "max", "rctype": "edit|new|log", "rcdir": "older",
        "format": "json", "formatversion": "2"
    })
    changes = payload.get("query", {}).get("recentchanges", [])
    save_json(OUT / "recent-changes.json", {
        "source": "https://stowiki.net/", "api": API_URL,
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "count": len(changes), "changes": changes
    })
    return len(changes)


def sync_asset_manifest():
    items = []
    continuation = {}
    while len(items) < MAX_ASSETS:
        params = {
            "action": "query", "list": "allimages", "ailimit": "max",
            "aiprop": "timestamp|url|size|mime|sha1|user",
            "format": "json", "formatversion": "2"
        }
        params.update(continuation)
        payload = api_get(params)
        items.extend(payload.get("query", {}).get("allimages", []))
        continuation = payload.get("continue", {})
        if not continuation:
            break
        time.sleep(0.15)
    save_json(OUT / "asset-manifest.json", {
        "source": "https://stowiki.net/", "api": API_URL,
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "count": len(items), "truncated": bool(continuation),
        "notice": "Metadata and original URLs only; binary assets are not mirrored.",
        "assets": items
    })
    return len(items)


def main():
    try:
        changes = sync_recent_changes()
        assets = sync_asset_manifest()
    except Exception as exc:
        print("STO Wiki sync failed: " + str(exc), file=sys.stderr)
        return 1
    print("Updated " + str(changes) + " recent changes and " + str(assets) + " asset records.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
