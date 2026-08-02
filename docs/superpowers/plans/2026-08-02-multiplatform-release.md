# VoxFlow Multiplatform Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the complete Windows application into current main and make CI, GitHub Release, the landing page, and all localized README files publish and describe macOS, Windows, and iOS artifacts from one version.

**Architecture:** Keep the macOS plist as the version source, extend the existing release metadata with a backward-compatible per-platform asset map, and build each platform in its native GitHub Actions runner. Platform jobs upload verified artifacts; a final publish job releases the complete set atomically and only then deploys the landing page.

**Tech Stack:** Swift 6/SwiftPM, Xcode/xcodebuild, Bash, Python 3, JavaScript/CSS/HTML, .NET 10/WPF, Rust 1.97, PowerShell, Inno Setup, GitHub Actions.

---

## File map

- `VoxFlow.Windows/`: imported Windows application, tests, native bridge, installer, and packaging scripts.
- `.github/workflows/windows-ci.yml`: authoritative Windows test/build/package workflow.
- `scripts/prepare-release.py`: writes versioned three-platform metadata and README asset names.
- `scripts/check-release-metadata.py`: executable release contract test.
- `docs/release.json`: backward-compatible macOS updater fields plus canonical `assets` map.
- `docs/index.html`, `docs/script.js`, `docs/styles.css`: localized three-platform download UI.
- `Apps/VoxFlowiOS/Scripts/export-adhoc-ipa.sh`: archives and exports the signed app plus keyboard extension.
- `Apps/VoxFlowiOS/Scripts/verify-signed-ios-ipa.sh`: checks signatures, profiles, bundle IDs, App Group, and registered-device profile type.
- `Makefile`: stable unsigned and Ad Hoc IPA entry points.
- `.github/workflows/ci.yml`: macOS/iOS quality and unsigned artifact jobs.
- `.github/workflows/release.yml`: macOS, Windows, and signed iOS build jobs plus atomic publisher.
- `.github/workflows/pages.yml`, `.github/workflows/deploy-landing.yml`: verify the macOS compatibility URL and all new platform URLs after deployment.
- `README.md`, `README.zh-CN.md`, `README.zh-TW.md`, `README.ja.md`, `README.ko.md`: localized platform matrix and install guidance.

### Task 1: Integrate the complete Windows branch

**Files:**
- Create: `VoxFlow.Windows/**`
- Create: `.github/workflows/windows-ci.yml`
- Modify: `agent-cli/Cargo.toml`
- Modify: `agent-cli/src/*.rs`
- Modify: `agent-cli/tests/*.rs`

- [ ] **Step 1: Prove the merge is structurally clean**

Run:

```bash
git merge-tree --write-tree origin/main origin/feat/windows-v1-dictation
```

Expected: exit 0 and one tree object ID, with no conflict messages.

- [ ] **Step 2: Merge the Windows implementation with an explicit merge commit**

Run:

```bash
git merge --no-ff origin/feat/windows-v1-dictation \
  -m "feat(windows): 合并 Windows 完整功能线" \
  -m "1) 目标与背景：将 Windows 听写、OCR、Agent 与文件转写功能并入当前三平台产品线。" \
  -m "2) 文件与行为：引入 VoxFlow.Windows、Windows CI、打包脚本和必要的 Rust Agent 共享能力。" \
  -m "3) 影响与兼容性：新增 Windows x64 实现；保留当前 main 的 macOS 与 iOS 行为，不引入旧 OpenSpec 文档。" \
  -m "4) 验证方式：合并前 merge-tree 无冲突；合并后运行治理脚本、Rust 测试，完整 WPF 构建交由 Windows CI。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

Expected: merge succeeds and `VoxFlow.Windows/` plus `.github/workflows/windows-ci.yml` exist.

- [ ] **Step 3: Verify the excluded OpenSpec documents did not enter the branch**

Run:

```bash
test ! -e openspec/changes/add-windows-file-transcription
git diff --name-only origin/main...HEAD | grep -q '^VoxFlow.Windows/'
```

Expected: both commands exit 0.

- [ ] **Step 4: Run portable Windows governance and shared Agent checks**

Run:

```bash
bash VoxFlow.Windows/tests/governance.test.sh
bash VoxFlow.Windows/tests/traceability.test.sh
bash VoxFlow.Windows/tests/windows-ci-contract.test.sh
bash VoxFlow.Windows/tests/check-no-secrets.test.sh
cargo fmt --manifest-path agent-cli/Cargo.toml --check
cargo test --manifest-path agent-cli/Cargo.toml
```

Expected: all portable checks pass. Record .NET/WPF/Installer validation as pending Windows runner evidence.

### Task 2: Extend the release metadata contract using TDD

**Files:**
- Modify: `scripts/check-release-metadata.py`
- Modify: `scripts/prepare-release.py`
- Modify: `docs/release.json`
- Modify: `docs/script.js`

- [ ] **Step 1: Make the checker require all four install artifacts**

Add these expected names after reading `version`:

```python
asset_names = {
    "macos": {"dmg": f"VoxFlow-{version}-macOS.dmg"},
    "windows": {
        "installer": f"VoxFlow-{version}-windows-x64-setup.exe",
        "portable": f"VoxFlow-{version}-windows-x64-portable.zip",
    },
    "ios": {"ipa": f"Mashangxie-{version}-iOS.ipa"},
}
```

Require every leaf in `release_json["assets"]` to contain the exact `name` and `downloadURL`, while continuing to require top-level `assetName` and `downloadURL` for the macOS updater compatibility contract.

- [ ] **Step 2: Run the checker and confirm the schema test fails**

Run:

```bash
make release-check
```

Expected: FAIL because `docs/release.json` does not yet contain `assets.macos`, `assets.windows`, and `assets.ios`.

- [ ] **Step 3: Generate one backward-compatible platform asset payload**

Add this helper to `scripts/prepare-release.py` and use it from `update_docs`:

```python
def release_assets(version: str, tag: str) -> dict[str, dict[str, dict[str, str]]]:
    base = f"https://github.com/xingbofeng/VoxFlow/releases/download/{tag}"

    def artifact(name: str) -> dict[str, str]:
        return {"name": name, "downloadURL": f"{base}/{name}"}

    return {
        "macos": {"dmg": artifact(f"VoxFlow-{version}-macOS.dmg")},
        "windows": {
            "installer": artifact(f"VoxFlow-{version}-windows-x64-setup.exe"),
            "portable": artifact(f"VoxFlow-{version}-windows-x64-portable.zip"),
        },
        "ios": {
            "ipa": artifact(f"Mashangxie-{version}-iOS.ipa"),
            "distribution": "ad-hoc",
        },
    }
```

Write `assets` into `docs/release.json`; set legacy `assetName` and `downloadURL` from `assets["macos"]["dmg"]`. Update the generated fallback object in `docs/script.js` with the same names.

- [ ] **Step 4: Regenerate metadata at the current version without bumping it**

Run:

```bash
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/VoxFlowApp/Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/VoxFlowApp/Resources/Info.plist)
python3 scripts/prepare-release.py --version "$version" --build "$build"
make release-check
```

Expected: the current version remains unchanged and `make release-check` passes.

- [ ] **Step 5: Review and commit the metadata contract**

Run:

```bash
git diff --check
git diff -- scripts/check-release-metadata.py scripts/prepare-release.py docs/release.json docs/script.js
git add scripts/check-release-metadata.py scripts/prepare-release.py docs/release.json docs/script.js
git commit -m "feat(release): 统一三平台发布资产契约" \
  -m "1) 目标与背景：让一个版本同时描述 macOS、Windows 和 iOS 可下载产物。" \
  -m "2) 文件与行为：扩展 release.json、准备脚本和一致性检查，保留 macOS 更新客户端兼容字段。" \
  -m "3) 影响与兼容性：新增 assets 平台映射；旧 assetName/downloadURL 继续指向 DMG。" \
  -m "4) 验证结果：release-check 先按旧 schema 失败，生成新 schema 后通过。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

### Task 3: Add a signed Ad Hoc IPA packaging path using TDD

**Files:**
- Create: `Apps/VoxFlowiOS/Scripts/export-adhoc-ipa.sh`
- Create: `Apps/VoxFlowiOS/Scripts/verify-signed-ios-ipa.sh`
- Modify: `Apps/VoxFlowiOS/Scripts/verify-ios-ipa-contract.sh`
- Modify: `Makefile`

- [ ] **Step 1: Extend the validator contract before implementing export**

Create `verify-signed-ios-ipa.sh` with the same payload checks as `verify-ios-ipa-contract.sh`, plus these required checks after unzipping:

```bash
codesign --verify --deep --strict "$APP_PATH"
codesign --verify --strict "$KEYBOARD_PATH"

APP_ENTITLEMENTS="$TMP_DIR/app-entitlements.plist"
KEYBOARD_ENTITLEMENTS="$TMP_DIR/keyboard-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" > "$APP_ENTITLEMENTS"
codesign -d --entitlements :- "$KEYBOARD_PATH" > "$KEYBOARD_ENTITLEMENTS"

[[ "$(plist_value "$APP_ENTITLEMENTS" ':com.apple.security.application-groups:0')" == "$APP_GROUP_ID" ]]
[[ "$(plist_value "$KEYBOARD_ENTITLEMENTS" ':com.apple.security.application-groups:0')" == "$APP_GROUP_ID" ]]
[[ -f "$APP_PATH/embedded.mobileprovision" ]]
[[ -f "$KEYBOARD_PATH/embedded.mobileprovision" ]]
```

Decode both profiles with `security cms -D -i`, require a non-empty `ProvisionedDevices` array, and require the profile application identifiers to end in the two expected bundle IDs.

- [ ] **Step 2: Prove the signed validator rejects the current unsigned IPA**

Run:

```bash
make ios-ipa
Apps/VoxFlowiOS/Scripts/verify-signed-ios-ipa.sh dist/ios/Mashangxie.ipa Apps/VoxFlowiOS
```

Expected: the unsigned build step succeeds, then signed validation fails at signature or embedded-profile validation.

- [ ] **Step 3: Implement deterministic Ad Hoc archive and export**

`export-adhoc-ipa.sh` must require six arguments: version, team ID, app profile specifier, keyboard profile specifier, archive path, and output directory. Generate an export options plist containing:

```xml
<key>method</key><string>ad-hoc</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>TEAM_ID</string>
<key>provisioningProfiles</key>
<dict>
  <key>com.mashangxie.ios</key><string>APP_PROFILE_SPECIFIER</string>
  <key>com.mashangxie.ios.keyboard</key><string>KEYBOARD_PROFILE_SPECIFIER</string>
</dict>
```

Archive with manual signing, export with `xcodebuild -exportArchive`, rename the result to `Mashangxie-<version>-iOS.ipa`, then call both IPA validators.

- [ ] **Step 4: Add stable Make targets**

Add `ios-ipa-adhoc` to `.PHONY` and define:

```make
ios-ipa-adhoc: ios-gen-project
	@test -n "$(MASHANGXIE_DEVELOPMENT_TEAM)" || (echo "Set MASHANGXIE_DEVELOPMENT_TEAM" && exit 2)
	@test -n "$(MASHANGXIE_APP_PROFILE_SPECIFIER)" || (echo "Set MASHANGXIE_APP_PROFILE_SPECIFIER" && exit 2)
	@test -n "$(MASHANGXIE_KEYBOARD_PROFILE_SPECIFIER)" || (echo "Set MASHANGXIE_KEYBOARD_PROFILE_SPECIFIER" && exit 2)
	Apps/VoxFlowiOS/Scripts/export-adhoc-ipa.sh \
		"$(VERSION)" "$(MASHANGXIE_DEVELOPMENT_TEAM)" \
		"$(MASHANGXIE_APP_PROFILE_SPECIFIER)" "$(MASHANGXIE_KEYBOARD_PROFILE_SPECIFIER)" \
		"$(IOS_RELEASE_ARCHIVE)" "$(IOS_IPA_DIR)"
```

- [ ] **Step 5: Run all locally possible iOS packaging checks and commit**

Run:

```bash
bash -n Apps/VoxFlowiOS/Scripts/export-adhoc-ipa.sh
bash -n Apps/VoxFlowiOS/Scripts/verify-signed-ios-ipa.sh
make ios-ipa
git diff --check
```

Expected: script syntax and unsigned IPA contract pass. Signed export remains pending until CI receives real Distribution credentials and profiles.

Commit after reviewing the full diff:

```bash
git add Makefile Apps/VoxFlowiOS/Scripts
git commit -m "feat(ios): 增加 Ad Hoc IPA 发布打包" \
  -m "1) 目标与背景：为已登记 UDID 的设备生成包含键盘扩展的可安装 IPA。" \
  -m "2) 文件与行为：新增手动签名 archive/export 脚本、签名校验器和 Make 入口。" \
  -m "3) 影响与兼容性：保留现有未签名 ios-ipa；新增路径仅在提供签名参数时启用。" \
  -m "4) 验证结果：Bash 语法与未签名 IPA 结构通过；真实 Ad Hoc 签名由发布 CI 验证。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

### Task 4: Make every main/PR CI package macOS, Windows, and unsigned iOS artifacts

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/windows-ci.yml`

- [ ] **Step 1: Run Windows CI for every main push and pull request**

Remove the workflow-level `paths` filters from `push` and `pull_request`. Keep `branches: [main]`, concurrency cancellation, and the existing 90-minute timeout so every candidate revision proves the Windows package still builds.

- [ ] **Step 2: Add a version-reading contract to Windows CI**

Before Windows packaging, read the plist version with PowerShell:

```powershell
[xml]$plist = Get-Content Sources/VoxFlowApp/Resources/Info.plist
$dict = $plist.plist.dict
$items = @($dict.ChildNodes | Where-Object NodeType -eq Element)
for ($index = 0; $index -lt $items.Count; $index += 2) {
  if ($items[$index].InnerText -eq "CFBundleShortVersionString") {
    "VOXFLOW_VERSION=$($items[$index + 1].InnerText)" | Out-File -FilePath $env:GITHUB_ENV -Append
  }
}
if (-not $env:VOXFLOW_VERSION -and -not (Select-String -Path $env:GITHUB_ENV -Pattern '^VOXFLOW_VERSION=')) { exit 1 }
```

Use `-Version "$env:VOXFLOW_VERSION"` in `prepare-windows-release.ps1`, and assert the exact EXE/ZIP names before artifact upload.

- [ ] **Step 3: Add macOS and unsigned iOS package artifacts to macOS CI**

After quality checks, always build an ad-hoc-signed macOS app ZIP and the unsigned iOS contract IPA:

```yaml
- name: Package macOS CI app
  run: |
    make build CODE_SIGN_IDENTITY=-
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/VoxFlowApp/Resources/Info.plist)
    ditto -c -k --sequesterRsrc --keepParent .build/release/VoxFlow.app "dist/VoxFlow-${version}-macOS.app.zip"
    echo "MACOS_CI_PACKAGE=dist/VoxFlow-${version}-macOS.app.zip" >> "$GITHUB_ENV"

- name: Upload macOS CI app
  uses: actions/upload-artifact@v4
  with:
    name: VoxFlow-macOS
    path: ${{ env.MACOS_CI_PACKAGE }}
    if-no-files-found: error

- name: Build unsigned iOS IPA contract artifact
  run: make ios-ipa

- name: Upload unsigned iOS IPA contract artifact
  uses: actions/upload-artifact@v4
  with:
    name: Mashangxie-ios-unsigned
    path: dist/ios/Mashangxie.ipa
    if-no-files-found: error
```

This artifact proves device payload structure on PRs; it is not presented as installable.

- [ ] **Step 4: Validate workflow syntax and imported Windows contracts**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); YAML.load_file(".github/workflows/windows-ci.yml")'
bash VoxFlow.Windows/tests/windows-ci-contract.test.sh
git diff --check
```

Expected: YAML parses and the Windows workflow contract passes.

- [ ] **Step 5: Review and commit CI packaging changes**

```bash
git add .github/workflows/ci.yml .github/workflows/windows-ci.yml VoxFlow.Windows/tests/windows-ci-contract.test.sh
git commit -m "ci(build): 打包 Windows 与 iOS 验证产物" \
  -m "1) 目标与背景：让普通 CI 覆盖三平台构建产物，而不依赖发布签名。" \
  -m "2) 文件与行为：Windows 使用 plist 统一版本并上传 EXE/ZIP，macOS runner 上传未签名 IPA 验证件。" \
  -m "3) 影响与兼容性：现有 macOS 检查保留；PR 不读取受保护的 iOS 发布 secrets。" \
  -m "4) 验证结果：工作流 YAML、Windows CI contract 与 diff 检查通过。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

### Task 5: Rebuild Release as parallel platform jobs with atomic publish

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Split version validation from builders**

Create a `metadata` job on Ubuntu that checks out the repository, runs `make release-check`, reads the plist using Python `plistlib`, validates tag equality, and emits `version` and `tag` outputs. Make `macos`, `windows`, and `ios` jobs depend on it.

The output step must write:

```bash
echo "version=$PLIST_VERSION" >> "$GITHUB_OUTPUT"
echo "tag=v$PLIST_VERSION" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 2: Preserve the signed macOS builder as its own job**

Move the existing certificate import, `make dmg`, Sentry dSYM upload, codesign, architecture, and checksum steps into `macos`. Upload exactly:

```yaml
path: |
  dist/VoxFlow-${{ needs.metadata.outputs.version }}-macOS.dmg
  dist/VoxFlow-${{ needs.metadata.outputs.version }}-macOS.dmg.sha256
```

- [ ] **Step 3: Add the authoritative Windows release builder**

Use `windows-latest`, .NET 10, Rust 1.97, and the same restore/test/build/native bridge/Inno Setup/package sequence as `windows-ci.yml`. Pass `${{ needs.metadata.outputs.version }}` to `prepare-windows-release.ps1`, generate SHA-256 files with `Get-FileHash`, and upload the exact EXE, ZIP, and two checksum files.

- [ ] **Step 4: Add the Ad Hoc iOS release builder**

Use these secret mappings without printing their values:

```yaml
env:
  IOS_P12_BASE64: ${{ secrets.MASHANGXIE_IOS_DISTRIBUTION_P12_BASE64 }}
  IOS_P12_PASSWORD: ${{ secrets.MASHANGXIE_IOS_DISTRIBUTION_P12_PASSWORD }}
  IOS_TEAM_ID: ${{ secrets.MASHANGXIE_IOS_TEAM_ID }}
  IOS_APP_PROFILE_BASE64: ${{ secrets.MASHANGXIE_IOS_APP_PROFILE_BASE64 }}
  IOS_KEYBOARD_PROFILE_BASE64: ${{ secrets.MASHANGXIE_IOS_KEYBOARD_PROFILE_BASE64 }}
```

Import the p12 into a temporary keychain, decode both profiles into `~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision`, extract their `Name` values, then call:

```bash
make ios-ipa-adhoc \
  VERSION="${{ needs.metadata.outputs.version }}" \
  MASHANGXIE_DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
  MASHANGXIE_APP_PROFILE_SPECIFIER="$APP_PROFILE_NAME" \
  MASHANGXIE_KEYBOARD_PROFILE_SPECIFIER="$KEYBOARD_PROFILE_NAME"
```

Run `verify-signed-ios-ipa.sh`, generate `.sha256`, and upload the IPA plus checksum.

- [ ] **Step 5: Publish only the complete artifact set**

Create `publish` with `needs: [metadata, macos, windows, ios]`. Download each artifact into `dist/release`, assert these eight files exist, and publish them with `softprops/action-gh-release@v2`:

```text
VoxFlow-<version>-macOS.dmg
VoxFlow-<version>-macOS.dmg.sha256
VoxFlow-<version>-windows-x64-setup.exe
VoxFlow-<version>-windows-x64-setup.exe.sha256
VoxFlow-<version>-windows-x64-portable.zip
VoxFlow-<version>-windows-x64-portable.zip.sha256
Mashangxie-<version>-iOS.ipa
Mashangxie-<version>-iOS.ipa.sha256
```

Keep landing deployment in a final job depending on `publish`, so a partial release cannot update the site.

- [ ] **Step 6: Validate and commit the Release workflow**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'
make release-check
git diff --check
```

Review the complete workflow and commit:

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): 聚合发布三平台安装包" \
  -m "1) 目标与背景：一个 GitHub Release 必须完整提供 macOS、Windows、iOS 产物。" \
  -m "2) 文件与行为：拆分平台构建、加入 Ad Hoc 签名与 Windows 打包，并由最终任务原子发布。" \
  -m "3) 影响与兼容性：任一平台失败即不发布；成功后才触发落地页部署。" \
  -m "4) 验证结果：YAML 与 release-check 通过；真实签名和 Windows 构建等待 GitHub runner。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

### Task 6: Update the landing page and deployment verification

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/script.js`
- Modify: `docs/styles.css`
- Modify: `.github/workflows/pages.yml`
- Modify: `.github/workflows/deploy-landing.yml`

- [ ] **Step 1: Replace the single download anchor with platform cards**

Use semantic markup with stable data attributes:

```html
<section class="platform-downloads" aria-labelledby="download-heading">
  <article class="platform-card" data-platform="macos">
    <a data-download="macos-dmg"></a>
  </article>
  <article class="platform-card" data-platform="windows">
    <a data-download="windows-installer"></a>
    <a data-download="windows-portable"></a>
  </article>
  <article class="platform-card" data-platform="ios">
    <a data-download="ios-ipa"></a>
  </article>
</section>
```

Keep a macOS fallback href for no-JavaScript/update compatibility, but populate all links from `release.assets` in `docs/script.js`.

- [ ] **Step 2: Add natural five-language copy**

For each language in `copy`, provide platform names, primary/secondary download labels, requirements, and the iOS restriction. The English meanings are:

```javascript
downloadHeading: "Choose your platform",
downloadMacOS: "Download DMG",
downloadWindows: "Download installer",
downloadWindowsPortable: "Portable ZIP",
downloadIOS: "Download Ad Hoc IPA",
downloadIOSMeta: "Registered devices only · includes the Mashangxie keyboard"
```

Write fluent Simplified Chinese, Traditional Chinese, Japanese, and Korean equivalents; do not derive visible text from key fragments.

- [ ] **Step 3: Style responsive cards without redesigning the site**

Use the existing color, type, radius, and focus tokens. Define a three-column desktop grid, two-column tablet grid, and one-column mobile grid. Ensure all links have visible `:focus-visible`, and make the Windows secondary link visually subordinate but still accessible.

- [ ] **Step 4: Extend Pages verification to all platform URLs**

In both deployment workflows, load `release["assets"]`, compare every artifact URL against the expected GitHub Release URL, and retain the existing top-level macOS `downloadURL` check. After deployment, fail if any platform asset name or URL is stale.

- [ ] **Step 5: Run static and browser verification**

Run:

```bash
make release-check
scripts/build-landing-site.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/pages.yml"); YAML.load_file(".github/workflows/deploy-landing.yml")'
git diff --check
```

Then serve the generated site and use the Codex Browser at desktop and mobile widths. Verify all four download links, five language selectors, keyboard focus, no horizontal overflow, and the visible Ad Hoc limitation.

- [ ] **Step 6: Review and commit landing changes**

```bash
git add docs/index.html docs/script.js docs/styles.css .github/workflows/pages.yml .github/workflows/deploy-landing.yml
git commit -m "feat(landing): 展示三平台下载入口" \
  -m "1) 目标与背景：落地页需要清晰提供 macOS、Windows 与 iOS 下载。" \
  -m "2) 文件与行为：加入响应式平台卡片、五语言文案和三平台部署后校验。" \
  -m "3) 影响与兼容性：保留 macOS fallback；明确 iOS 仅支持已登记设备 Ad Hoc 安装。" \
  -m "4) 验证结果：release-check、站点构建、YAML 与桌面/移动浏览器检查通过。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

### Task 7: Update all localized README files

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `README.zh-TW.md`
- Modify: `README.ja.md`
- Modify: `README.ko.md`
- Modify: `scripts/prepare-release.py`
- Modify: `scripts/check-release-metadata.py`

- [ ] **Step 1: Add release-check requirements before editing copy**

For every README, require exactly one occurrence of each versioned filename:

```python
expected = [
    f"VoxFlow-{version}-macOS.dmg",
    f"VoxFlow-{version}-windows-x64-setup.exe",
    f"VoxFlow-{version}-windows-x64-portable.zip",
    f"Mashangxie-{version}-iOS.ipa",
]
```

Run `make release-check` and expect failure because Windows and iOS references are missing.

- [ ] **Step 2: Add the same information architecture in all five languages**

Each README must include:

```markdown
| Platform | Minimum requirement | Package | Notes |
| --- | --- | --- | --- |
| macOS | macOS 15+ | DMG | VoxFlow desktop app |
| Windows | Windows 10/11 x64 | Installer or Portable ZIP | Installer is recommended |
| iOS | Compatible iPhone/iPad | Ad Hoc IPA | Device UDID must be registered |
```

Translate the prose naturally and accurately. Keep the iOS name “码上写 / Mashangxie”, do not claim that iOS has desktop OCR/Agent/file-transcription parity, and explain that the IPA contains the keyboard extension.

- [ ] **Step 3: Teach prepare-release to update all filenames**

Replace each of the four semantic-versioned filename patterns in every README, not arbitrary version-looking text:

```python
patterns = {
    r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-macOS\.dmg": f"VoxFlow-{version}-macOS.dmg",
    r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-setup\.exe": f"VoxFlow-{version}-windows-x64-setup.exe",
    r"VoxFlow-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-portable\.zip": f"VoxFlow-{version}-windows-x64-portable.zip",
    r"Mashangxie-[0-9]+\.[0-9]+\.[0-9]+-iOS\.ipa": f"Mashangxie-{version}-iOS.ipa",
}
```

- [ ] **Step 4: Regenerate, validate, review, and commit README copy**

Run:

```bash
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/VoxFlowApp/Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/VoxFlowApp/Resources/Info.plist)
python3 scripts/prepare-release.py --version "$version" --build "$build"
make release-check
git diff --check
```

Review all five translations, then commit:

```bash
git add README.md README.zh-CN.md README.zh-TW.md README.ja.md README.ko.md scripts/prepare-release.py scripts/check-release-metadata.py
git commit -m "docs(readme): 补齐三平台安装说明" \
  -m "1) 目标与背景：README 需要与 Release 和落地页一致展示三个平台。" \
  -m "2) 文件与行为：五语言 README 增加支持矩阵、四个产物和各平台安装限制。" \
  -m "3) 影响与兼容性：桌面与 iOS 能力分开描述；prepare-release 同步全部文件名。" \
  -m "4) 验证结果：release-check 与 diff 检查通过，五份文案已逐份人工复核。" \
  -m "Co-authored-by: OpenAI Codex <codex@openai.com>"
```

### Task 8: Run the completion gate and create the PR

**Files:**
- Review: all changes against `origin/main`

- [ ] **Step 1: Run release, documentation, and portable Windows gates**

```bash
make release-check
make i18n-check
bash VoxFlow.Windows/tests/governance.test.sh
bash VoxFlow.Windows/tests/traceability.test.sh
bash VoxFlow.Windows/tests/windows-ci-contract.test.sh
bash VoxFlow.Windows/tests/check-no-secrets.test.sh
cargo fmt --manifest-path agent-cli/Cargo.toml --check
cargo test --manifest-path agent-cli/Cargo.toml
```

Expected: all pass.

- [ ] **Step 2: Run macOS/iOS local release gates**

```bash
swift test
make debug
make build
make ios-ipa
```

Expected: all pass; the unsigned IPA validator confirms the app and keyboard payload. Do not claim signed-device installation from this local step.

- [ ] **Step 3: Audit the complete diff against the objective**

Run:

```bash
git status --short
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
git log --oneline origin/main..HEAD
test ! -e openspec/changes/add-windows-file-transcription
```

Confirm the diff contains Windows implementation, four install assets in Release, three-platform landing/README content, no old OpenSpec docs, and no secret values.

- [ ] **Step 4: Push and open a ready PR**

```bash
git push -u origin codex/multiplatform-release
gh pr create --base main --head codex/multiplatform-release \
  --title "feat(release): 统一 macOS、Windows 与 iOS 发布" \
  --body-file /tmp/voxflow-multiplatform-pr.md
```

The PR body must list the four artifacts, Ad Hoc UDID restriction, local verification, and the two runner-only pending checks: Windows WPF/Installer and real iOS signing.

- [ ] **Step 5: Verify GitHub CI and fix failures**

Watch the PR checks until macOS CI, Windows CI, and all policy checks complete. If a check fails, use the `gha` skill, reproduce locally where possible, fix with TDD, commit, push, and re-check. Do not merge while any required check is pending or failing.

- [ ] **Step 6: Prove release readiness without publishing an unintended version**

Use workflow validation and PR artifacts as evidence. Only trigger the tag Release workflow after the user supplies the five iOS signing secrets, confirms the release version/build and release notes, and explicitly authorizes tag publication. A successful release must contain all eight files listed in Task 5 before the goal can be marked complete.
