# STO Wiki Companion

Native iOS companion and scheduled content mirror for https://stowiki.net/.

## Repository contents

- `Sources/STOWikiCompanion/STOWikiCompanionApp.swift`: native SwiftUI wiki search starter.
- `project.yml`: XcodeGen project definition, targeting iOS 17+.
- `scripts/sync_stowiki.py`: exports main-namespace page text, recent changes, and uploaded-media metadata; downloads media files from approved source hosts.
- `.github/workflows/sync-wiki.yml`: scheduled mirror and manual sync.
- Workflow artifact `stowiki-mirror-N`: generated page export, downloaded media, asset manifest, recent changes, and mirror summary.

## Automatic updates

GitHub Actions runs every 12 hours and can be started manually from **Actions → Mirror STO Wiki content and media → Run workflow**. Each successful run uploads a downloadable mirror artifact retained for 90 days. The mirror is generated at runtime rather than committed to Git history, avoiding huge binary files and noisy commits.

To download it, open the workflow run in GitHub Actions and use the **Artifacts** section at the bottom of the run summary. The artifact contains:

- `pages.jsonl`: one JSON object per main-namespace article, with title, source URL, revision ID, and plain-text extract.
- `recent-changes.json`: the recent-change index returned by the API.
- `asset-manifest.json`: uploaded media metadata, original source URLs, local paths, and per-file download status.
- `assets/`: downloaded media files where the API provides an approved HTTPS source URL.
- `mirror-summary.json`: counts and size totals for that run.

## Coverage and limits

The sync uses the MediaWiki Action API, pagination, a descriptive user agent, retries, and a small delay between requests. It exports main-namespace page text rather than raw wikitext or revision history. It downloads uploaded media exposed by the API, subject to these configurable limits:

- Up to 10,000 media records.
- 5,000 MB total downloaded media.
- 100 MB per media file.
- Media hosts allowed by default: `stowiki.net`, `www.stowiki.net`, `static.wikia.nocookie.net`, and `images.weserv.nl`.

These safeguards prevent a scheduled run from unexpectedly consuming unlimited storage. If the summary or manifest reports truncation, skipped hosts, size limits, or failed downloads, the artifact is not a guaranteed complete mirror. You can adjust `STOWIKI_MAX_ASSETS`, `STOWIKI_MAX_TOTAL_MB`, `STOWIKI_MAX_FILE_MB`, and `STOWIKI_API_DELAY_SECONDS` in the workflow after checking repository storage and source-site capacity. Files served by a different host must be explicitly reviewed before adding that host to the allowlist.

The export does not include every possible site component: site CSS/JavaScript, templates as editable source, private/restricted pages, raw revision histories, or externally embedded media that the API does not list. The native iOS app is still a starter search UI; the mirror pipeline is a separate automated export.

## Generate the Xcode project

Install XcodeGen (for example, with Homebrew), then from the repository root run:

    xcodegen generate

Open `STOWikiCompanion.xcodeproj` in Xcode. Set your development team if installing on a device, then run on an iOS 17+ simulator or device.

## API endpoint

The sync assumes `https://stowiki.net/api.php` supports the standard MediaWiki Action API and anonymous access. If the endpoint returns an error, disables access, or changes its schema, the workflow fails visibly rather than bypassing the site's controls.
