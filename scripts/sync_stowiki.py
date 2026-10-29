#!/usr/bin/env python3
"""Mirror STO Wiki page text and uploaded media through its public MediaWiki API.

The mirror is emitted as generated data for a GitHub Actions artifact, not committed
to Git history. Respect the source site's rate limits and access controls.
"""
import hashlib
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

API_URL = os.environ.get("STOWIKI_API_URL", "https://stowiki.net/w/api.php")
SITE_URL = "https://stowiki.net/"
USER_AGENT = "STOWikiCompanionMirror/1.0 (GitHub Actions; contact via https://github.com/rike4545/STOWikiCompanion)"
OUT = Path("mirror")
MAX_ASSETS = int(os.environ.get("STOWIKI_MAX_ASSETS", "10000"))
MAX_TOTAL_MB = int(os.environ.get("STOWIKI_MAX_TOTAL_MB", "5000"))
MAX_FILE_MB = int(os.environ.get("STOWIKI_MAX_FILE_MB", "100"))
SLEEP_SECONDS = float(os.environ.get("STOWIKI_API_DELAY_SECONDS", "0.15"))
ALLOWED_MEDIA_HOSTS = {
    "stowiki.net", "www.stowiki.net", "static.wikia.nocookie.net",
    "images.weserv.nl"
}


def api_get(params):
    params = dict(params)
    params.setdefault("format", "json")
    params.setdefault("formatversion", "2")
    params.setdefault("maxlag", "5")
    url = API_URL + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
    )
    last_error = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.status != 200:
                    raise RuntimeError("API returned HTTP " + str(response.status))
                payload = json.loads(response.read().decode("utf-8"))
                if "error" in payload:
                    raise RuntimeError("MediaWiki API error: " + str(payload["error"]))
                return payload
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as exc:
            last_error = exc
            if attempt < 4:
                time.sleep(min(2 ** attempt, 20))
    raise RuntimeError("Could not query API: " + str(last_error))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def safe_filename(name, fallback):
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._")
    return (name or fallback)[:180]


def sync_pages():
    path = OUT / "pages.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    continuation = {}
    with path.open("w", encoding="utf-8") as output:
        while True:
            params = {
                "action": "query",
                "generator": "allpages",
                "gaplimit": "max",
                "gapnamespace": "0",
                "prop": "extracts|info",
                "explaintext": "1",
                "exsectionformat": "plain",
                "inprop": "url",
            }
            params.update(continuation)
            payload = api_get(params)
            for page in payload.get("query", {}).get("pages", []):
                output.write(json.dumps({
                    "pageid": page.get("pageid"),
                    "title": page.get("title"),
                    "url": page.get("fullurl"),
                    "revision_id": page.get("lastrevid"),
                    "text": page.get("extract", ""),
                }, ensure_ascii=False) + "\n")
                count += 1
            continuation = payload.get("continue", {})
            if not continuation:
                break
            time.sleep(SLEEP_SECONDS)
    return count


def sync_recent_changes():
    payload = api_get({
        "action": "query", "list": "recentchanges",
        "rcprop": "title|timestamp|ids|sizes|flags|comment",
        "rclimit": "max", "rctype": "edit|new|log", "rcdir": "older",
    })
    changes = payload.get("query", {}).get("recentchanges", [])
    write_json(OUT / "recent-changes.json", {
        "source": SITE_URL, "api": API_URL,
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "count": len(changes), "changes": changes,
    })
    return len(changes)


def sync_assets():
    assets_dir = OUT / "assets"
    assets_dir.mkdir(parents=True, exist_ok=True)
    items = []
    continuation = {}
    total_bytes = sum(p.stat().st_size for p in assets_dir.rglob("*") if p.is_file())
    max_total_bytes = MAX_TOTAL_MB * 1024 * 1024
    max_file_bytes = MAX_FILE_MB * 1024 * 1024
    stopped_for_limit = False

    while len(items) < MAX_ASSETS:
        params = {
            "action": "query", "list": "allimages", "ailimit": "max",
            "aiprop": "timestamp|url|size|mime|sha1|user",
        }
        params.update(continuation)
        payload = api_get(params)
        batch = payload.get("query", {}).get("allimages", [])
        for item in batch:
            original_url = item.get("url", "")
            parsed = urlparse(original_url)
            host = (parsed.hostname or "").lower()
            record = dict(item)
            record["downloaded"] = False
            record["local_path"] = None
            if parsed.scheme != "https" or host not in ALLOWED_MEDIA_HOSTS:
                record["download_status"] = "skipped_unapproved_host"
                items.append(record)
                continue
            declared_size = int(item.get("size") or 0)
            if declared_size > max_file_bytes:
                record["download_status"] = "skipped_file_size_limit"
                items.append(record)
                continue
            if total_bytes + declared_size > max_total_bytes:
                record["download_status"] = "stopped_total_size_limit"
                items.append(record)
                stopped_for_limit = True
                break
            extension = Path(parsed.path).suffix[:12]
            if not extension or not re.fullmatch(r"\.[A-Za-z0-9]{1,10}", extension):
                extension = mimetypes.guess_extension(item.get("mime", "")) or ".bin"
            digest = hashlib.sha256(original_url.encode("utf-8")).hexdigest()[:16]
            filename = safe_filename(item.get("name", "asset"), "asset")
            destination = assets_dir / (digest + "_" + filename)
            if destination.suffix == "":
                destination = destination.with_suffix(extension)
            try:
                request = urllib.request.Request(original_url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(request, timeout=90) as response:
                    if response.status != 200:
                        raise RuntimeError("HTTP " + str(response.status))
                    content_length = response.headers.get("Content-Length")
                    if content_length and int(content_length) > max_file_bytes:
                        raise RuntimeError("download exceeds per-file size limit")
                    with destination.open("wb") as output:
                        downloaded = 0
                        while True:
                            chunk = response.read(1024 * 1024)
                            if not chunk:
                                break
                            downloaded += len(chunk)
                            if downloaded > max_file_bytes or total_bytes + downloaded > max_total_bytes:
                                raise RuntimeError("download exceeds configured size limit")
                            output.write(chunk)
                total_bytes += destination.stat().st_size
                record["downloaded"] = True
                record["local_path"] = str(destination).replace("\\", "/")
                record["download_status"] = "ok"
            except Exception as exc:
                try:
                    destination.unlink(missing_ok=True)
                except OSError:
                    pass
                record["download_status"] = "download_failed: " + str(exc)[:240]
            items.append(record)
            time.sleep(SLEEP_SECONDS)
        continuation = payload.get("continue", {})
        if stopped_for_limit or not continuation:
            break
        time.sleep(SLEEP_SECONDS)

    write_json(OUT / "asset-manifest.json", {
        "source": SITE_URL, "api": API_URL,
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "listed_count": len(items),
        "downloaded_count": sum(1 for x in items if x.get("downloaded")),
        "total_downloaded_bytes": total_bytes,
        "total_size_limit_mb": MAX_TOTAL_MB,
        "per_file_limit_mb": MAX_FILE_MB,
        "truncated": bool(continuation) or stopped_for_limit or len(items) >= MAX_ASSETS,
        "notice": "Uploaded media retrieved from the MediaWiki API. See each record's original URL and download status.",
        "assets": items,
    })
    return len(items), sum(1 for x in items if x.get("downloaded")), total_bytes


def main():
    try:
        OUT.mkdir(parents=True, exist_ok=True)
        pages = sync_pages()
        changes = sync_recent_changes()
        assets, downloaded, total_bytes = sync_assets()
        write_json(OUT / "mirror-summary.json", {
            "source": SITE_URL,
            "synced_at": datetime.now(timezone.utc).isoformat(),
            "pages_exported": pages,
            "recent_changes_exported": changes,
            "assets_listed": assets,
            "assets_downloaded": downloaded,
            "assets_downloaded_bytes": total_bytes,
            "max_assets": MAX_ASSETS,
            "max_total_mb": MAX_TOTAL_MB,
            "max_file_mb": MAX_FILE_MB,
        })
    except Exception as exc:
        print("STO Wiki mirror failed: " + str(exc), file=sys.stderr)
        return 1
    print(f"Exported {pages} pages, {changes} recent changes, and downloaded {downloaded}/{assets} media files ({total_bytes} bytes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
