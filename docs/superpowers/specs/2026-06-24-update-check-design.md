# VoxFlow Update Check Design

## Background

VoxFlow is distributed as a native macOS app through GitHub Releases and DMG assets. The current app already exposes the local version through `CFBundleShortVersionString` and has a Help entry that links to the latest release page.

The first update feature should work without Apple Developer ID signing or notarization. Because unsigned self-replacement can create Gatekeeper friction and trust problems, this design intentionally avoids automatic installation.

## Goal

Add a lightweight in-app update check that can tell users when a newer stable VoxFlow release is available and take them to the download page.

The feature must be fully testable locally without publishing real GitHub Releases.

## Non-Goals

- Do not integrate Sparkle in this phase.
- Do not download DMG files inside the app.
- Do not replace or relaunch the app automatically.
- Do not require Apple Developer ID signing.
- Do not change the existing release signing, notarization, or DMG publication flow.

## User Experience

VoxFlow checks for updates automatically after launch, but only after a short delay so startup, menu bar registration, permissions, and dictation setup stay responsive.

Automatic checks run at most once every 24 hours. If no update is available, the app stays quiet. If the network fails during an automatic check, the app also stays quiet and only logs the failure.

Users can manually check from the app menu and from the Help view. Manual checks ignore the 24-hour throttle and always show a result:

- A newer version shows an update prompt.
- The same or older latest version shows "当前已是最新版".
- Network or parsing failure shows a concise failure message.

When a newer version is found, the prompt shows:

- Current version.
- Latest version.
- Short release notes summary when available.
- `下载更新`.
- `稍后提醒`.
- `忽略此版本`.

`下载更新` opens the GitHub Release page. If a matching DMG asset is present, the implementation may open the asset URL instead, but the release page is the safer default because it also exposes release notes and checksums.

`忽略此版本` stores the ignored version. Future automatic checks do not prompt for that version again. Manual checks may still show the result so users can reverse course by downloading from the prompt.

## Architecture

The update checker is split into small units under `Sources/VoxFlowApp/Updates/`.

### Models

`SemanticVersion` parses and compares app versions. It accepts both `1.6.1` and `v1.6.1`. Invalid versions do not trigger update prompts.

`RemoteRelease` represents the normalized latest release:

- `version`
- `tagName`
- `releasePageURL`
- `downloadURL`
- `releaseNotes`
- `isDraft`
- `isPrerelease`

### Release Client

`ReleaseMetadataClient` is the fetch abstraction:

```swift
protocol ReleaseMetadataClient {
    func fetchLatestRelease() async throws -> RemoteRelease
}
```

`GitHubReleaseClient` implements the production path by requesting:

```text
https://api.github.com/repos/xingbofeng/VoxFlow/releases/latest
```

It parses `tag_name`, `html_url`, `body`, `draft`, `prerelease`, and `assets`. It prefers a DMG asset matching `VoxFlow-*-macOS.dmg` when present.

Draft and prerelease releases are not treated as stable update candidates in phase one.

### Decision Service

`UpdateCheckService` coordinates current version, remote release, ignored version, and check mode.

The service returns an explicit result:

- `updateAvailable(RemoteRelease)`
- `upToDate`
- `ignored(RemoteRelease)`
- `failed(UpdateCheckError)`
- `throttled`

Automatic checks may return `throttled` or silently map failures to logs at the orchestration layer. Manual checks surface `upToDate` and `failed` to the user.

### State Store

`UpdateCheckStateStore` persists lightweight state in UserDefaults:

- Last automatic check time.
- Ignored version.

Tests must use isolated suite names with `UUID()` to avoid cross-test pollution.

### Prompt Presenter

`UpdatePromptPresenter` owns AppKit presentation and opening URLs through `NSWorkspace`.

It should not fetch data or compare versions. It only presents a given `UpdateCheckResult`.

## Debug And Mock Strategy

Local debugging must not require publishing GitHub Releases.

The update checker supports three data sources:

1. Production GitHub API.
2. Fixture JSON loaded from a local file.
3. Named debug mocks.

Debug-only environment variables:

```bash
VOXFLOW_UPDATE_CHECK_MOCK=newer make run-dev
VOXFLOW_UPDATE_CHECK_MOCK=same make run-dev
VOXFLOW_UPDATE_CHECK_MOCK=network-error make run-dev
VOXFLOW_UPDATE_CHECK_FIXTURE=/absolute/path/to/latest-newer.json make run-dev
```

Supported mock names:

- `newer`
- `same`
- `network-error`

The fixture override accepts a GitHub Releases API-style JSON file. This lets developers test parser behavior and UI presentation with realistic payloads.

All environment-variable mock wiring is compiled only for Debug builds:

```swift
#if DEBUG
// choose mock or fixture client
#endif
```

Release builds always use `GitHubReleaseClient`.

## Test Fixtures

Add fixtures under `Tests/VoxFlowAppTests/Fixtures/Updates/`:

- `latest-newer.json`
- `latest-same.json`
- `latest-prerelease.json`
- `latest-malformed.json`
- `latest-no-dmg.json`

These fixtures cover the normal happy path and parser failure paths without real network calls.

## App Integration

`AppDelegate` assembles the update components and schedules an automatic check roughly 30 seconds after launch.

`AppMainMenuBuilder` adds `检查更新...` to the application menu. The menu action routes back to `AppDelegate` or a small coordinator object that calls the service in manual mode and presents the result.

`HelpView` adds a "检查更新" action near the existing version/release entry. If the existing view model wiring makes this invasive, the first implementation may keep Help unchanged and ship the menu action only.

Logging should follow the existing `AppLogger` style and avoid logging release notes or unnecessary network payloads.

## Error Handling

Automatic checks:

- Ignore network, decoding, and invalid-version failures from the user perspective.
- Log enough context to diagnose failures.

Manual checks:

- Show a short failure alert for network, decoding, or missing release metadata.
- Do not show raw JSON or stack traces.

Invalid local or remote versions never trigger an update prompt.

## Testing Plan

Unit tests:

- `SemanticVersion` ordering, including `1.6.10 > 1.6.2`.
- `GitHubReleaseClient` decoding using fixtures.
- Draft and prerelease payloads do not become stable candidates.
- Missing DMG asset still produces a release-page fallback.
- `UpdateCheckService` returns update, up-to-date, ignored, failed, and throttled results correctly.
- `UpdateCheckStateStore` persists and reads state using isolated UserDefaults suites.

Manual debug verification:

- `VOXFLOW_UPDATE_CHECK_MOCK=newer make run-dev` shows the update prompt.
- `VOXFLOW_UPDATE_CHECK_MOCK=same make run-dev` shows "当前已是最新版" for manual checks.
- `VOXFLOW_UPDATE_CHECK_MOCK=network-error make run-dev` shows a manual failure alert.
- Ignoring a version suppresses future automatic prompts for that version.

Project gates:

- `swift test --filter Update`
- `swift test`
- `make debug`
- `make build`

If unrelated existing worktree issues block full gates, report the exact command, error location, and whether the failure is related to update checking.

## Acceptance Criteria

- Current `1.6.1`, remote `1.6.2`: update prompt appears.
- Current `1.6.1`, remote `1.6.1`: manual check reports up to date.
- Current `1.6.10`, remote `1.6.2`: no update prompt appears.
- Prerelease payloads do not trigger stable update prompts.
- Automatic checks do not repeat within 24 hours.
- Manual checks bypass the 24-hour throttle.
- Ignored versions do not trigger automatic prompts.
- Local mock and fixture modes can exercise the update UI without publishing a real release.
