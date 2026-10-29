# STO Wiki Companion

Native iOS companion and scheduled change index for https://stowiki.net/.

## Repository contents

- Sources/STOWikiCompanion/STOWikiCompanionApp.swift: native SwiftUI wiki search starter.
- scripts/sync_stowiki.py: refreshes recent-change metadata and an image/file manifest from the MediaWiki API.
- .github/workflows/sync-wiki.yml: scheduled workflow and manual sync.
- data/recent-changes.json: recent changes returned by the API.
- data/asset-manifest.json: asset metadata and original source URLs, not copied binary assets.

## Automatic updates

GitHub Actions runs every 12 hours and can be started manually from Actions, then Sync STO Wiki metadata, then Run workflow. It updates metadata manifests from the website API and commits changes to main.

The sync uses the MediaWiki API, a descriptive user agent, and API continuation rather than crawling HTML pages. It does not download and republish every image or article. The image manifest keeps original source URLs so the app can display assets from the wiki host.

## Why assets are linked instead of mirrored

The wiki's copyright policy distinguishes community-authored content from Star Trek game text, characters, screenshots, and other third-party material. Some content may be CC BY-NC-SA unless otherwise noted, while other assets may have different restrictions. A bulk mirror of every image and article could redistribute material without the right license. This repository therefore tracks source metadata and links to originals. Before storing or redistributing binary assets, verify each item's license or obtain permission from the rightsholder.

Reference: https://sto.fandom.com/wiki/STOWiki:Policy/Copyright. Verify the current stowiki.net site's own terms and API availability before publishing or distributing an app.

## Build the iOS app

1. Open Xcode and create an iOS App project named STOWikiCompanion using SwiftUI.
2. Set the deployment target to iOS 17 or later.
3. Replace the generated app entry point with the Swift file in Sources/STOWikiCompanion/.
4. Run on an iPhone simulator or device.

This starter is intentionally small. A production app should add persistent bookmarks, cached article extracts, richer native article formatting, attribution and license display, tests, and a privacy policy.

## API endpoint

The sync assumes https://stowiki.net/api.php supports the standard MediaWiki Action API. If the endpoint returns 403, changes its schema, or disables anonymous API access, the workflow will fail visibly rather than bypassing the site's controls.
