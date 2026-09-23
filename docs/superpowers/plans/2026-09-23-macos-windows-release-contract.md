# macOS + Windows Release Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a version-consistent macOS and Windows release without presenting an unsigned iOS IPA as a downloadable artifact, while retaining iOS source and continuous integration coverage.

**Architecture:** The checked-in release metadata becomes the sole declaration of the platforms actually published for a tag. Release preparation, metadata validators, GitHub Release packaging, the website, and localized README download tables all derive their expectations from that declaration. macOS remains the primary updater asset; iOS source versioning and unsigned CI packaging continue for every release even when iOS is not in the published platform set.

**Tech Stack:** Python 3 release tooling and unittest, GitHub Actions YAML, JavaScript/HTML landing page, Markdown documentation, SwiftPM/Make, and .NET project metadata.

---

## File structure and responsibilities

- `scripts/prepare-release.py` — parses a validated platform set, synchronizes macOS/iOS/Windows source versions, generates platform-aware static release metadata and download documentation.
- `scripts/check-release-metadata.py` — verifies source version parity and every checked-in release surface against `publishedPlatforms`.
- `scripts/check-release-assets-published.py` — asks the GitHub Release API only for assets declared as published.
- `scripts/check-deployed-release-metadata.py` — compares the full declared release shape between checked-in and deployed metadata, including absence of an unselected iOS asset.
- `scripts/release_platforms.py` — small shared module defining the supported platform sets, expected asset kinds, and metadata parsing/validation used by all release Python tools.
- `Tests/ReleaseMetadataTests/test_release_platforms.py` — unit tests for accepted/rejected platform declarations and derived assets.
- `Tests/ReleaseMetadataTests/test_release_assets_published.py` — behavior tests for two-platform and three-platform GitHub Release asset gates.
- `Tests/ReleaseMetadataTests/test_deployed_release_metadata.py` — behavior tests for two-platform and three-platform deployed landing metadata equality.
- `Tests/ReleaseMetadataTests/test_release_metadata.py` — subprocess tests that exercise version parity and platform-aware generated source metadata.
- `Makefile` — exposes `RELEASE_PLATFORMS` to `prepare-release` and leaves the historical three-platform default explicit.
- `.github/workflows/release.yml` — reads the checked-in platform declaration before scheduling iOS signing, requires only selected jobs, and verifies only selected artifacts.
- `VoxFlow.Windows/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj` — stores the same source version as macOS/iOS for the release being prepared.
- `docs/release.json` — declares the version, primary macOS updater asset, `publishedPlatforms`, and only real downloadable assets.
- `docs/script.js` / `docs/index.html` — show platform download CTAs only when the release declaration has a URL; static iOS fallbacks remain hidden when no IPA was published.
- `README.md`, `README.zh-CN.md`, `README.zh-TW.md`, `README.ja.md`, `README.ko.md` — list only actual release downloads and give a non-download iOS-source availability note when iOS is unselected.
- `.github/release-notes/TEMPLATE.md` — permits generated release notes to list only the actual assets for the selected platform set.
- `Tests/VoxFlowAppTests/App/BrandIdentityTests.swift` — updates the existing workflow contract assertion to cover conditional iOS release behavior rather than unconditional iOS signing.

### Task 1: Define and test the declared release platform contract

**Files:**
- Create: `scripts/release_platforms.py`
- Create: `Tests/ReleaseMetadataTests/test_release_platforms.py`
- Modify: `scripts/check-release-assets-published.py:18-72`
- Modify: `scripts/check-deployed-release-metadata.py:13-87`

- [ ] **Step 1: Write failing tests for the platform declaration and its derived assets**

```python
def test_two_platform_release_requires_exactly_macos_and_windows_assets(self) -> None:
    metadata = {
        "publishedPlatforms": ["macos", "windows"],
        "assets": {
            "macos": {"dmg": {"name": "VoxFlow-1.16.0-macOS.dmg"}},
            "windows": {
                "installer": {"name": "VoxFlow-1.16.0-windows-x64-setup.exe"},
                "portable": {"name": "VoxFlow-1.16.0-windows-x64-portable.zip"},
            },
        },
    }
    self.assertEqual(
        release_platforms.documented_asset_names(metadata),
        (
            "VoxFlow-1.16.0-macOS.dmg",
            "VoxFlow-1.16.0-windows-x64-setup.exe",
            "VoxFlow-1.16.0-windows-x64-portable.zip",
        ),
    )

def test_rejects_unselected_ios_asset_and_invalid_platform_order(self) -> None:
    with self.assertRaises(release_platforms.PlatformContractError):
        release_platforms.parse_published_platforms(["windows", "macos"])
```

- [ ] **Step 2: Run the new test to verify it fails because the shared module does not exist**

Run: `python3 Tests/ReleaseMetadataTests/test_release_platforms.py`

Expected: FAIL with an import error for `release_platforms`.

- [ ] **Step 3: Implement one shared, strict platform contract**

```python
SUPPORTED_PLATFORM_SETS = (
    ("macos", "windows"),
    ("macos", "windows", "ios"),
)
ASSET_KINDS = {
    "macos": ("dmg",),
    "windows": ("installer", "portable"),
    "ios": ("ipa",),
}

def parse_published_platforms(value: object) -> tuple[str, ...]:
    if not isinstance(value, list) or tuple(value) not in SUPPORTED_PLATFORM_SETS:
        raise PlatformContractError(
            "release.publishedPlatforms must be [\"macos\", \"windows\"] or "
            "[\"macos\", \"windows\", \"ios\"]."
        )
    return tuple(value)
```

Implement `documented_asset_names(metadata)` to parse `publishedPlatforms`, require exactly the matching `assets` keys, require every platform's defined asset kinds, and reject extra platform keys. Keep the iOS `distribution == "ad-hoc"` requirement only when `ios` is declared.

- [ ] **Step 4: Refactor both existing API/deployed gates to import the shared contract**

Replace their fixed iOS-inclusive tuples with `release_platforms.documented_asset_names(metadata)` / `release_platforms.metadata_paths(metadata)`. The deployed gate must compare `publishedPlatforms` and compare the union of required metadata paths so an unexpected deployed `assets.ios` object is reported as a mismatch.

- [ ] **Step 5: Run contract and existing behavior tests**

Run: `python3 Tests/ReleaseMetadataTests/test_release_platforms.py && python3 Tests/ReleaseMetadataTests/test_release_assets_published.py && python3 Tests/ReleaseMetadataTests/test_deployed_release_metadata.py`

Expected: PASS, including a macOS+Windows-only fixture, a complete three-platform fixture, and failures for omitted declared assets or unexpected iOS metadata.

- [ ] **Step 6: Commit the isolated contract change**

```bash
git add scripts/release_platforms.py scripts/check-release-assets-published.py scripts/check-deployed-release-metadata.py Tests/ReleaseMetadataTests/test_release_platforms.py Tests/ReleaseMetadataTests/test_release_assets_published.py Tests/ReleaseMetadataTests/test_deployed_release_metadata.py
git commit -m "fix(release): 声明实际发布平台"
```

### Task 2: Make release preparation synchronize source versions and generate only real download surfaces

**Files:**
- Modify: `scripts/prepare-release.py:1-184`
- Modify: `scripts/check-release-metadata.py:1-218`
- Modify: `VoxFlow.Windows/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj`
- Modify: `.github/release-notes/TEMPLATE.md`
- Create: `Tests/ReleaseMetadataTests/test_release_metadata.py`

- [ ] **Step 1: Write failing subprocess tests for a two-platform preparation and version parity**

```python
def test_prepare_release_for_macos_and_windows_omits_ipa_metadata(self) -> None:
    completed = run_prepare("1.16.0", "27", "macos,windows")
    self.assertEqual(completed.returncode, 0, completed.stderr)
    release = json.loads((root / "docs/release.json").read_text())
    self.assertEqual(release["publishedPlatforms"], ["macos", "windows"])
    self.assertNotIn("ios", release["assets"])

def test_release_check_rejects_windows_version_drift(self) -> None:
    write_windows_version("1.15.0")
    completed = run_release_check()
    self.assertNotEqual(completed.returncode, 0)
    self.assertIn("Windows version is stale", completed.stderr)
```

Use a copied temporary repository fixture so the test never changes the active checkout.

- [ ] **Step 2: Run the new test to verify current preparation fails it**

Run: `python3 Tests/ReleaseMetadataTests/test_release_metadata.py`

Expected: FAIL because `prepare-release.py` has no `--platforms` argument, always writes iOS metadata, and does not update the Windows project version.

- [ ] **Step 3: Implement explicit `--platforms` preparation**

Add `--platforms` to `scripts/prepare-release.py`, accept the comma form `macos,windows` or `macos,windows,ios`, and call `release_platforms.parse_published_platforms`. Always update the macOS plist, iOS project/plists, and the Windows `<Version>`, `<AssemblyVersion>`, and `<FileVersion>` values to the selected version/build-derived values. Generate:

```json
"publishedPlatforms": ["macos", "windows"],
"assets": {
  "macos": {"dmg": {"name": "VoxFlow-1.16.0-macOS.dmg", "downloadURL": "..."}},
  "windows": {"installer": {"name": "...setup.exe", "downloadURL": "..."}, "portable": {"name": "...portable.zip", "downloadURL": "..."}}
}
```

Only add the iOS IPA and ad-hoc distribution object when `ios` is selected. Ensure the generated release notes list macOS + Windows asset names for two-platform releases and adds the iOS IPA line only for a three-platform release.

- [ ] **Step 4: Implement a platform-aware source metadata verifier**

Have `scripts/check-release-metadata.py` import `release_platforms`. Verify the platform list, the exact expected generated asset names/URLs for selected platforms, iOS `ad-hoc` only when selected, one occurrence of each actual asset in each localized README, and parity among the macOS plist, iOS project/plists, and Windows project version fields. It must reject an unselected iOS asset, stale Windows version, or iOS download URL in a two-platform static fallback.

- [ ] **Step 5: Expose the platform choice through Make**

```make
RELEASE_PLATFORMS ?= macos,windows,ios

prepare-release:
	python3 scripts/prepare-release.py --version "$(VERSION)" --build "$(BUILD)" --platforms "$(RELEASE_PLATFORMS)"
```

Keep the historical three-platform default so ordinary future releases remain strict unless the release operator explicitly opts into `RELEASE_PLATFORMS=macos,windows`.

- [ ] **Step 6: Run the isolated release metadata suite and source checker**

Run: `python3 Tests/ReleaseMetadataTests/test_release_metadata.py && make release-check`

Expected: PASS on the checked-in release declaration; the temporary fixture confirms both supported platform sets and Windows version drift detection.

- [ ] **Step 7: Commit the release preparation change**

```bash
git add Makefile scripts/prepare-release.py scripts/check-release-metadata.py VoxFlow.Windows/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj .github/release-notes/TEMPLATE.md Tests/ReleaseMetadataTests/test_release_metadata.py
git commit -m "fix(release): 同步三端源码版本"
```

### Task 3: Make the GitHub Release workflow select only declared package jobs

**Files:**
- Modify: `.github/workflows/release.yml:21-415`
- Modify: `Tests/VoxFlowAppTests/App/BrandIdentityTests.swift`

- [ ] **Step 1: Write or update the workflow contract assertion before changing YAML**

```swift
XCTAssertTrue(workflow.contains("publishedPlatforms"))
XCTAssertTrue(workflow.contains("contains(steps.platforms.outputs.value, 'ios')"))
XCTAssertTrue(workflow.contains("needs: [macos, windows, ios]"))
XCTAssertTrue(workflow.contains("always()"))
XCTAssertTrue(workflow.contains("only selected release assets"))
```

Replace the old unconditional iOS assertion with behavior-level checks showing that macOS/Windows remain required, iOS is conditionally packaged, and the publisher validates declared artifacts. Keep the assertion limited to the published workflow contract, not arbitrary source text.

- [ ] **Step 2: Run the focused test and verify the old workflow fails its updated contract**

Run: `swift test --filter BrandIdentityTests`

Expected: FAIL until the workflow declares and consumes the platform set.

- [ ] **Step 3: Add a metadata reader job and conditional iOS packaging**

At the start of `release.yml`, add a Linux `release_metadata` job that reads `docs/release.json`, validates it with `scripts/release_platforms.py`, exposes a comma-separated platform output, and fails closed for an invalid declaration. Make the iOS job conditional on the output containing `ios`; macOS and Windows jobs remain unconditional.

- [ ] **Step 4: Make publishing tolerate only the intended skipped iOS job**

Keep `needs: [macos, windows, ios]`, set the publisher condition to a tag plus `always()`, and require:

```yaml
needs.macos.result == 'success' &&
needs.windows.result == 'success' &&
(needs.release_metadata.outputs.includes_ios != 'true' || needs.ios.result == 'success')
```

Download artifacts using the metadata's selection, and replace fixed shell `test -f` lines with one Python invocation that validates the downloaded filenames/checksums against the checked-in platform contract. The macOS SHA remains required in every release; the iOS IPA SHA is required only if `ios` was declared.

- [ ] **Step 5: Run focused source validation**

Run: `swift test --filter BrandIdentityTests && ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'`

Expected: PASS. The YAML parse may warn about GitHub-specific expressions only if Ruby cannot interpret them; the document must still load with no syntax error.

- [ ] **Step 6: Commit the conditional release workflow**

```bash
git add .github/workflows/release.yml Tests/VoxFlowAppTests/App/BrandIdentityTests.swift
git commit -m "fix(release): 按声明发布平台打包"
```

### Task 4: Render only actual download CTAs and update every localized README

**Files:**
- Modify: `docs/script.js:1-26,914-916`
- Modify: `docs/index.html:7-18,92-126,263-274`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `README.zh-TW.md`
- Modify: `README.ja.md`
- Modify: `README.ko.md`

- [ ] **Step 1: Write a failing static landing test for an unselected iOS platform**

Add a test to `Tests/ReleaseMetadataTests/test_release_metadata.py` that prepares `macos,windows`, asserts both iOS CTA elements have `hidden`, asserts no current-release IPA GitHub URL appears in `docs/index.html`, and asserts the JavaScript has no unconditional `release.assets.ios.ipa` access or macOS fallback for an unknown platform.

- [ ] **Step 2: Run it to demonstrate the current fallback is unsafe**

Run: `python3 Tests/ReleaseMetadataTests/test_release_metadata.py`

Expected: FAIL because the static hero CTA contains an iOS IPA URL and the JavaScript falls back to the macOS URL.

- [ ] **Step 3: Implement metadata-driven CTA visibility**

Use optional asset access and an explicit URL map:

```javascript
const releaseDownloadURLs = {
  macos: releaseAssetURL(release.assets.macos.dmg.name),
  windows: releaseAssetURL(release.assets.windows.installer.name),
  ...(release.assets.ios?.ipa
    ? { ios: releaseAssetURL(release.assets.ios.ipa.name) }
    : {})
};

document.querySelectorAll("[data-download-platform]").forEach((element) => {
  const url = releaseDownloadURLs[element.dataset.downloadPlatform];
  element.hidden = !url;
  if (url) element.href = url;
  else element.removeAttribute("href");
});
```

Mark both iOS fallback cards `hidden` and remove the versioned iOS href. Let `prepare-release.py` unhide and populate only when `ios` is selected. Update current-download copy in all five JavaScript language entries and static fallbacks to say macOS + Windows; retain iOS feature/source wording only where it clearly does not promise an IPA.

- [ ] **Step 4: Update five README release tables from the platform declaration**

For a macOS+Windows release, generate exactly two platform rows (macOS DMG; Windows installer and portable archive), update their current versioned names, remove the iOS installation prerequisite, and add a natural-language localized non-download note that iOS source remains in the repository and a signed IPA will return in a future release. Do not keep an old IPA filename or URL in a current download table.

- [ ] **Step 5: Run static metadata, localization, and diff checks**

Run: `python3 Tests/ReleaseMetadataTests/test_release_metadata.py && make release-check && make i18n-check && git diff --check`

Expected: PASS. The tests prove both CTA locations hide iOS without an IPA and all five READMEs enumerate only published assets.

- [ ] **Step 6: Commit website and documentation behavior**

```bash
git add docs/script.js docs/index.html docs/release.json README.md README.zh-CN.md README.zh-TW.md README.ja.md README.ko.md Tests/ReleaseMetadataTests/test_release_metadata.py
git commit -m "fix(docs): 仅展示已发布下载项"
```

### Task 5: Prepare the confirmed macOS+Windows release and verify the complete branch

**Files:**
- Modify: versioned files generated by `make prepare-release VERSION=<confirmed> BUILD=<confirmed> RELEASE_PLATFORMS=macos,windows`
- Create: `.github/release-notes/v<confirmed>.md` when absent

- [ ] **Step 1: Obtain explicit release approval**

Confirm the exact version, build, user-facing release-note content, and release timing/tag with the user. Do not create a tag, release, or versioned release-note file before this confirmation.

- [ ] **Step 2: Generate the release metadata with the confirmed values**

Run: `make prepare-release VERSION=<confirmed-version> BUILD=<confirmed-build> RELEASE_PLATFORMS=macos,windows`

Expected: macOS/iOS/Windows source versions are equal; `docs/release.json` declares only `macos` and `windows`; website and README current download references name the selected version; any new release-note file contains no IPA asset line.

- [ ] **Step 3: Write accurate release notes**

Edit `.github/release-notes/v<confirmed-version>.md` through `apply_patch` to describe only user-observable shipped work and list exactly:

```markdown
- macOS DMG：`VoxFlow-<confirmed-version>-macOS.dmg`
- Windows 安装包：`VoxFlow-<confirmed-version>-windows-x64-setup.exe`
- Windows 便携包：`VoxFlow-<confirmed-version>-windows-x64-portable.zip`
```

Do not imply an iOS IPA has been shipped. Mention iOS source/CI only if useful and state it is not an installable release asset.

- [ ] **Step 4: Run the complete pre-merge verification set**

Run:

```bash
python3 Tests/ReleaseMetadataTests/test_release_platforms.py
python3 Tests/ReleaseMetadataTests/test_release_assets_published.py
python3 Tests/ReleaseMetadataTests/test_deployed_release_metadata.py
python3 Tests/ReleaseMetadataTests/test_release_metadata.py
make release-check
make i18n-check
swift test --filter BrandIdentityTests
ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' .github/workflows/ci.yml .github/workflows/release.yml .github/workflows/deploy-landing.yml .github/workflows/pages.yml
git diff --check
```

Expected: every local check exits zero. Record any unavailable platform-specific build tooling separately rather than representing it as a local pass.

- [ ] **Step 5: Review all staged changes and commit in the repository format**

Review `git diff --cached --check` and `git diff --cached` before committing. Use a Chinese conventional commit subject and a body that explicitly covers target/background, file/behavior changes, compatibility, and verification, followed by:

```text
Co-authored-by: OpenAI Codex <codex@openai.com>
```

- [ ] **Step 6: Push and wait for the authoritative remote CI gates**

Run: `git push origin HEAD` and wait for both the macOS full CI and Windows offline x64 CI for the exact pushed SHA to conclude `success`. Do not re-run another workflow while the desired run is live.

### Task 6: Merge, publish, deploy, and prove the released download surfaces

**Files:**
- No additional source edits expected after merged CI succeeds.

- [ ] **Step 1: Merge the reviewed release branch to `main`**

Use GitHub CLI to merge the approved pull request only after all required checks for its exact head SHA are successful. Fetch `origin/main` and verify the merge includes iOS, Windows, and macOS source version parity before creating the tag.

- [ ] **Step 2: Create and push the approved version tag on merged `main`**

Run: `git tag -a v<confirmed-version> -m 'release: v<confirmed-version>' <merged-main-sha>` then `git push origin v<confirmed-version>`.

Expected: GitHub's release workflow sees `publishedPlatforms=["macos","windows"]`, signs/macOS packages, builds the Windows installer/portable archive, skips iOS signing intentionally, and publishes exactly three binary assets plus their applicable checksums.

- [ ] **Step 3: Verify the GitHub Release artifacts authoritatively**

Wait for the tag workflow to pass. Query `gh release view v<confirmed-version> --json isDraft,isPrerelease,assets,url` and require the Mac DMG, Windows setup EXE, and Windows portable ZIP. Check each selected `browser_download_url` with an HTTP success response. Confirm no `Mashangxie-<confirmed-version>-iOS.ipa` is linked as an installable asset.

- [ ] **Step 4: Verify deployed landing surfaces and README source**

Wait for the landing deployment workflows. Fetch `https://mashangxie.app/release.json`, `https://xingbofeng.github.io/VoxFlow/release.json`, and any configured public domain metadata; compare each with `scripts/check-deployed-release-metadata.py --expected docs/release.json`. Open the rendered site through the configured browser capability and confirm hero and final CTA areas show only macOS + Windows downloads. Confirm the five top-level README files list the same three real filenames and no current-release IPA link.

- [ ] **Step 5: Record completion evidence**

Report the exact merged SHA, CI run URLs/conclusions, GitHub Release URL and asset names, public landing URLs and metadata check result, documentation surface checks, and any iOS limitation (source/CI preserved; official IPA intentionally deferred).
