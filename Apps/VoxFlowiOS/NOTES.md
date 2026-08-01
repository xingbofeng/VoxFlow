# VoxFlowiOS — Mashangxie iOS Implementation Notes

This file records the gold-standard source copy strategy, upstream baselines, target
naming, and Phase 1 / Phase 2 validation boundaries for the Mashangxie iOS Keyboard
Extension work tracked under
`openspec/changes/build-mashangxie-ios-keyboard/`.

The authoritative proposal, design, specs, and task list live under that OpenSpec
change directory. This file is the implementation-note companion referenced by tasks
1.1-1.7, 7.10, 13.4, 13.7, and 13.8.

## 1.1 Dictus upstream baseline

- **Upstream repo**: Dictus iOS (local copy under `.codex/upstream-sources/dictus-ios/`)
- **Source commit**: `7264b1d892adfddd1d9cf3a5f7c4debb37b00019`
- **License**: MIT License — `Copyright (c) 2026 PIVI Solutions`. Full text at
  `.codex/upstream-sources/dictus-ios/LICENSE`. License attribution must remain
  available in the repository (see task 13.6).
- **Local copy policy**: This is a direct source copy, NOT a submodule and NOT a
  fork. The directory under `.codex/upstream-sources/` is reference-only; copied
  files are placed under `Apps/VoxFlowiOS/` and adapted to the Mashangxie targets.

### Copied directories (Phase 1 scope)

| Upstream path | Target path (under `Apps/VoxFlowiOS/`) | Purpose |
|---|---|---|
| `DictusApp/App/` | `VoxFlowiOS/App/` | App lifecycle (AppDelegate / SceneDelegate if needed) |
| `DictusApp/Audio/UnifiedAudioEngine.swift` + audio helpers | `VoxFlowiOS/Audio/` | Microphone capture and audio session |
| `DictusApp/DictationCoordinator.swift` | `VoxFlowiOS/Dictation/DictationCoordinator.swift` | Recording lifecycle + ASR callback orchestration |
| `DictusApp/Views/` (selected) | `VoxFlowiOS/Views/` | Copied Dictus App UI shell |
| `DictusApp/Onboarding/` | `VoxFlowiOS/Onboarding/` | Setup guidance |
| `DictusApp/Services/` (voice-related slices) | `VoxFlowiOS/Services/` | Sound feedback, permission, diagnostics |
| `DictusApp/Models/` (recording/language/state) | `VoxFlowiOS/Models/` | App-level models |
| `DictusApp/Resources/` (localization key structure, assets) | `VoxFlowiOS/Resources/` | Five-language strings, theme assets |
| `DictusKeyboard/` (full Keyboard UI tree) | `Keyboard/` | Complete Keyboard Extension |
| `DictusKeyboard/KeyboardState.swift` | `Keyboard/KeyboardState.swift` | Keyboard-side state machine |
| `DictusKeyboard/KeyboardViewController.swift` | `Keyboard/KeyboardViewController.swift` | Extension entry point |
| `DictusKeyboard/Views/` | `Keyboard/Views/` | Recording overlay, waveform, toolbar, candidate bar |
| `DictusKeyboard/TextPrediction/` | `Keyboard/TextPrediction/` | Candidate surface |
| `DictusKeyboard/TouchHandling/` | `Keyboard/TouchHandling/` | Key touch handling |
| `DictusKeyboard/Vendored/` | `Keyboard/Vendored/` | AOSPTrie / Controllers / Models / Views needed by keyboard |
| `DictusKeyboard/KeyboardLayouts.swift`, `KeyboardMetrics.swift`, `InputView.swift`, `KeyboardRootView.swift` | `Keyboard/` | Layout data, metrics, input view, root view |
| `DictusCore/Sources/DictusCore/AppGroup.swift` | `Shared/AppGroup.swift` | App Group wrapper |
| `DictusCore/Sources/DictusCore/SharedKeys.swift` | `Shared/SharedKeys.swift` | Shared defaults keys |
| `DictusCore/Sources/DictusCore/DarwinNotifications.swift` | `Shared/DarwinNotifications.swift` | Cross-process notifications |
| `DictusCore/Sources/DictusCore/DictationStatus.swift` | `Shared/DictationStatus.swift` | Shared status enum |
| `DictusCore/Sources/DictusCore/PersistentLog.swift` + `Logger.swift` | `Shared/` | Shared logging |
| `DictusCore/Sources/DictusCore/HapticFeedback.swift` | `Shared/HapticFeedback.swift` | Haptics |
| `DictusCore/Sources/DictusCore/Design/` | `Shared/Design/` | AnimatedMicButton, BrandWaveform, ProcessingAnimation, Theme |
| `DictusCore/Sources/DictusCore/KeyboardLayoutData.swift`, `KeyboardMode.swift` | `Shared/` (or `Keyboard/Models/`) | Layout constants shared by app + keyboard |

### Excluded directories (Phase 1 out-of-scope)

- `DictusApp/` references to **WhisperKit**, **Parakeet**, **model download**,
  **model manager**, **model selection provider**, and **French local model assets**.
- `DictusKeyboard/` model-provider hooks that transitively require WhisperKit /
  Parakeet / Dictus model dependencies.
- Dictus original build/release scripts and planning/debug docs under
  `Dictus/`, `scripts/`, `tools/`, `docs/`.
- Dictus `LiveActivityManager` / `DictusLiveActivityAttributes` /
  `LiveActivityStateMachine` are copied only as future entry points; they MUST NOT
  block Phase 1 acceptance (see proposal §"Widget / Live Activity / Dynamic
  Island"). ActivityKit / Widget targets are deferred.

## 1.2 Hamster upstream baseline (Phase 2)

- **Upstream repo**: Hamster (local copy under `.codex/upstream-sources/Hamster/`)
- **Source commit**: `65693706d01fc6c19ed6071968e542b0a2ef3f36`
- **License**: MIT License — `Copyright (c) 2025 xiao.fu`. Full text at
  `.codex/upstream-sources/Hamster/LICENSE.txt`. License attribution must remain
  available in the repository (see task 13.6).
- **Local copy policy**: Same as Dictus — direct copy, not a submodule.

### Phase 2 dependency expectations

| Upstream path | Target path (under `Apps/VoxFlowiOS/`) | Purpose |
|---|---|---|
| `Packages/RimeKit/` (Swift / ObjC / C bridge + binary deps) | `ChineseInput/RimeKit/` | Rime runtime bridge |
| `Packages/HamsterKeyboardKit/Sources/RimeContext/` | `ChineseInput/RimeContext/` | Rime context, candidate, schema state |
| `Packages/HamsterKit/Sources/T9/` | `ChineseInput/T9/` | T9 constants, digit-to-letter mapping, pinyin restoration |
| Hamster Chinese 26-key + 9-key layout/action data | `ChineseInput/Layouts/` | Layout providers for Dictus shell |
| Built-in Rime schema/dict resources | `ChineseInput/Resources/Schemas/` | Rime Ice (`rime_ice`) resources copied from `iDvel/rime-ice`, including upstream `t9.schema.yaml`, dependency dictionaries, Lua helpers, and OpenCC resources. |
| Hamster binary/vendor dependencies (`librime`, OpenCC, yaml-cpp, leveldb, marisa, etc.) | `ChineseInput/RimeKit/Frameworks/` | Prebuilt xcframeworks following Hamster's working route |

Phase 2 MUST reuse Hamster's binary/vendor approach rather than rebuilding `librime`,
OpenCC, yaml-cpp, leveldb, marisa, or similar native dependencies from scratch
(see `specs/ios-chinese-input/spec.md` "Hamster binary/vendor route is allowed").

### Phase 2 excluded scope

- Hamster's whole App UI / visual shell (Dictus UI remains authoritative).
- Full user-facing Rime scheme import / export / file server / CloudKit sync UI
  (Phase 2 only reserves the extension point; see task 10.7).
- Hamster components that conflict with the copied Dictus UI shell.

## 1.3 `Apps/VoxFlowiOS/project.yml` review — required changes

Current state: a single `VoxFlowiOS` application target with `com.voxflow.ios` bundle
id, iOS 17 deployment target, no App Group, no URL scheme, no Keyboard Extension,
no shared target. It depends on `VoxFlowMobileCore`, `VoxFlowASRRuntime`,
`VoxFlowAudio`, `VoxFlowProviderCloudCore`, `VoxFlowProviderApple`,
`VoxFlowProviderTencentCloud`, `VoxFlowProviderAliyunDashScope`,
`VoxFlowProviderVolcengine`.

Required changes for Mashangxie Phase 1:

1. **bundleIdPrefix**: keep `com.voxflow` for the XcodeGen prefix, but override
   `PRODUCT_BUNDLE_IDENTIFIER` per-target to `com.mashangxie.ios`,
   `com.mashangxie.ios.keyboard`. (Phase 1 keeps physical directory
   `Apps/VoxFlowiOS/`; only system identifiers move to `mashangxie`.)
2. **New targets**:
   - `Mashangxie` (application, replaces current `VoxFlowiOS` target name)
   - `MashangxieKeyboard` (`app-extension`, iOS Keyboard Extension)
   - `Shared` (framework / static library for App Group + shared state)
   - `ChineseInput` (Phase 2 framework for RimeKit + RimeContext + T9 + schemas)
   - `RimeKitObjC` (Phase 2 native ObjC/C wrapper boundary for copied Hamster
     RimeKit)
3. **Entitlements files**:
   - `VoxFlowiOS/Mashangxie.entitlements` — App Group `group.com.mashangxie.ios`
     + keychain access group if needed later.
   - `Keyboard/Keyboard.entitlements` — same App Group. Keyboard Full Access is
     declared separately by `RequestsOpenAccess` in `Keyboard/Info.plist`.
4. **URL scheme**: register `mashangxie` in the main app's `Info.plist` via
   `CFBundleURLTypes`.
5. **App embeds Keyboard Extension**: `Mashangxie` target depends on
   `MashangxieKeyboard` with `embed: true`.
6. **Resources**: split resources between app target and keyboard target; the
   keyboard target must ship its own `Resources/<lang>.lproj/Localizable.strings`
   for visible keyboard strings.
7. **Dependencies**:
   - `Mashangxie` (app) depends on `Shared` + the existing VoxFlow provider
     products used by the ASR bridge.
   - `MashangxieKeyboard` (extension) depends on `Shared` ONLY for Phase 1 voice
     path — keyboard extension MUST NOT link `VoxFlowASRRuntime` or cloud
     providers directly (extension-safe only, see task 8.3).
8. **iOS deployment target**: stay at iOS 17 (task 2.7).
9. **Code signing**: Phase 1 dev builds keep `CODE_SIGNING_REQUIRED: "NO"` for
   simulator; real-device validation needs paid signing (task 9.x).
10. **XcodeGen generation**: must still succeed after changes (task 2.8).

## 1.4 XcodeGen target name decisions

| XcodeGen target name | Type | Bundle id | Notes |
|---|---|---|---|
| `Mashangxie` | `application` | `com.mashangxie.ios` | Main app. Embeds `MashangxieKeyboard`. |
| `MashangxieKeyboard` | `app-extension` | `com.mashangxie.ios.keyboard` | iOS Keyboard Extension. |
| `Shared` | `framework` | (none — embedded in app + extension) | App Group, SharedKeys, DarwinNotifications, DictationStatus, design components, logs. |
| `ChineseInput` | `framework` | `com.mashangxie.ios.chineseinput` | RimeKit + RimeContext + T9 + schemas. Created for Phase 2 and embedded by the keyboard. |
| `RimeKitObjC` | `framework` | `com.mashangxie.ios.rimekitobjc` | ObjC/C wrapper module for copied Hamster RimeKit native bridge. |

### Branding rules for source symbols (per design §5)

- **General Swift symbols stay brand-neutral**: `KeyboardState`,
  `DictationCoordinator`, `UnifiedAudioEngine`, `RecordingOverlay`, `SharedKeys`,
  `DarwinNotifications`, `DictationStatus`, `KeyboardViewController`,
  `KeyboardRootView`, `InputView`, etc. Do NOT prepend `VoxFlow` or `Mashangxie`.
- **System-unique identifiers use `mashangxie`**:
  - App bundle id: `com.mashangxie.ios`
  - Keyboard bundle id: `com.mashangxie.ios.keyboard`
  - App Group: `group.com.mashangxie.ios`
  - URL scheme: `mashangxie`
  - Darwin notification prefix: `com.mashangxie.ios`
- **Visible brand strings**: English `Mashangxie`, Simplified Chinese `码上写`.
- **Physical directory**: `Apps/VoxFlowiOS/` stays as-is for Phase 1 (per design
  §5 and proposal). Only system identifiers move.

## 1.5 Phase 1 validation boundary

Phase 1 formal acceptance REQUIRES all of the following:

1. Real iOS App + Keyboard Extension installed on a physical iPhone with valid
   signing (paid Apple Developer Program or working local signing).
2. Manual enablement of the Mashangxie keyboard in iOS Settings > General >
   Keyboard > Keyboards.
3. Full Access enabled when the selected provider or shared behavior requires it.
4. WeChat (or equivalent host app with a real text input field) validation:
   focus field → switch to Mashangxie keyboard → tap voice → speak → stop →
   final text inserted into the host field through `textDocumentProxy.insertText`.

The following are PROBES only and MUST NOT be reported as Phase 1 completion:

- **AltStore / SideStore**: low-cost probe for install/Extension feasibility.
  App Group, entitlements, and keyboard extension behavior may be unstable. A
  successful AltStore/SideStore probe does NOT satisfy Phase 1 acceptance.
- **Simulator**: iOS Simulator cannot exercise the real Keyboard Extension
  selection flow in a third-party host app the same way a physical device does.
  Simulator builds are static/build validation only.
- **Mock / static checks**: unit tests, source scans, and resource checks support
  implementation correctness but do not satisfy the WeChat insertion requirement.

If formal validation cannot be completed because signing, entitlements, App Group,
developer account, or device installation is unavailable, the report MUST identify
the exact blocker and separate static / simulator / AltStore / SideStore / true
Keyboard Extension results (see `specs/ios-keyboard-dictation/spec.md` "Validation
reports signing limitations honestly").

## 1.6 Swift version boundary

The Mashangxie iOS project keeps the main app and existing VoxFlow provider bridge
on **Swift 6**. The copied Dictus `Shared` and `Keyboard` targets are intentionally
compiled as **Swift 5** with `SWIFT_STRICT_CONCURRENCY=minimal`.

Rationale:

- The copied Dictus keyboard tree is large and UI-heavy; rewriting it for strict
  Swift 6 concurrency would violate the gold standard of copying upstream code
  whenever possible.
- A global Swift 5 downgrade is not acceptable because it would also downgrade
  the Mashangxie app target and our existing ASR provider bridge.
- A trial Swift 6 build of the copied keyboard stack fails first in upstream /
  third-party code such as DeviceKit generated static properties and copied
  Dictus UI actor-isolation assumptions. Keeping only the copied layers on Swift
  5 contains that compatibility cost.
- Swift 6 remains the default for `Mashangxie`, root SwiftPM packages, and the
  provider bridge. This preserves the existing project direction while allowing
  the Dictus UI/state machine to stay close to upstream.

Allowed edits inside copied Dictus layers are limited to build-enabling changes,
identifier replacement, App Group / URL scheme replacement, green theme hooks, and
provider bridge boundaries. Do not convert the copied UI tree into a new house
style during Phase 1.

## 1.7 Source copy manifest

This manifest is the local source-of-truth for copied upstream blocks. It records
the upstream path, local path, copied status, and the reason for any adaptation.

### Dictus Phase 1 copy manifest

| Upstream path | Local path | Status | Adaptation notes |
|---|---|---|---|
| `DictusCore/Sources/DictusCore/AppGroup.swift` | `Shared/AppGroup.swift` | Copied | App Group changed to `group.com.mashangxie.ios`. |
| `DictusCore/Sources/DictusCore/SharedKeys.swift` | `Shared/SharedKeys.swift` | Copied/adapted | Key prefix changed to `mashangxie.`; model keys removed. |
| `DictusCore/Sources/DictusCore/DarwinNotifications.swift` | `Shared/DarwinNotifications.swift` | Copied/adapted | Notification prefix changed to `com.mashangxie.ios`. |
| `DictusCore/Sources/DictusCore/DictationStatus.swift` | `Shared/DictationStatus.swift` | Copied | Brand-neutral enum kept. |
| `DictusCore/Sources/DictusCore/PersistentLog.swift`, `Logger.swift`, `LogEvent.swift` | `Shared/` | Copied/adapted | Logger renamed where needed to avoid app symbol collision. |
| `DictusCore/Sources/DictusCore/Design/` | `Shared/Design/` | Copied/adapted | Visual structure retained; accent colors changed to Mashangxie green. |
| `DictusCore/Sources/DictusCore/Languages/`, `TextCorrection/`, dictionary helpers | `Shared/` | Copied | Kept for copied keyboard prediction/text-correction behavior. |
| `DictusKeyboard/KeyboardViewController.swift` | `Keyboard/KeyboardViewController.swift` | Copied/adapted | Bundle/target wiring changed to Mashangxie extension. |
| `DictusKeyboard/KeyboardState.swift` | `Keyboard/KeyboardState.swift` | Copied/adapted | App Group, URL scheme, provider/model gates changed. |
| `DictusKeyboard/KeyboardRootView.swift`, `InputView.swift`, `KeyboardLayouts.swift`, `KeyboardMetrics.swift` | `Keyboard/` | Copied/adapted | Full keyboard UI retained. |
| `DictusKeyboard/Views/` | `Keyboard/Views/` | Copied/adapted | Recording overlay, waveform, toolbar, full-access banner retained. |
| `DictusKeyboard/TextPrediction/`, `TouchHandling/`, `Vendored/` | `Keyboard/` | Copied/adapted | AOSPTrie resources converted to current local resource names. |
| `DictusApp/Audio/UnifiedAudioEngine.swift` | `VoxFlowiOS/Audio/UnifiedAudioEngine.swift` | Copied/adapted | Native capture retained; emits `VoxFlowAudio.AudioFrame` for existing ASR providers. |
| `DictusApp/Audio/ObjCExceptionCatcher.h/.m` | `VoxFlowiOS/Audio/ObjCExceptionCatcher.h/.m` | Copied | Bridging header wired through app target. |
| `DictusApp/DictationCoordinator.swift` | `VoxFlowiOS/Dictation/DictationCoordinator.swift` | Copied/adapted | Model transcription service replaced by Apple Speech/cloud provider bridge. |
| `DictusApp/Views/MainTabView.swift` | `VoxFlowiOS/Views/MainTabView.swift` | Copied/adapted | Three-tab shell, overlay, and cold-start structure retained; labels/theme localized. |
| `DictusApp/Views/HomeView.swift` | `VoxFlowiOS/Views/HomeView.swift` | Copied/adapted | Dictus model-status dashboard retained; `ModelManager` now maps models to Mashangxie providers. |
| `DictusApp/Views/ModelManagerView.swift`, `ModelCardView.swift`, `GaugeBarView.swift`, `ModelLoadingOverlay.swift`, `CyclingLoadingText.swift` | `VoxFlowiOS/Views/` | Copied/adapted | Dictus Models tab UI, full-screen preparation overlay, waveform, completion state, and loading text cycle retained; model download actions are bridged to provider selection/configuration readiness. |
| `DictusApp/Views/SettingsView.swift`, `SoundSettingsView.swift`, `LicensesView.swift` | `VoxFlowiOS/Views/` | Copied/adapted | Dictus grouped settings UI retained; visible strings/theme localized where Mashangxie differs. |
| `DictusApp/Services/SoundFeedbackService.swift` | `VoxFlowiOS/Services/SoundFeedbackService.swift` | Copied/adapted | Dictus sound feedback retained; Swift 6 main-actor isolation added for cached players. |
| `DictusApp/Views/RecordingView.swift` | `VoxFlowiOS/Views/RecordingView.swift` | Copied/adapted | Uses `DictationCoordinator` provider bridge; visible strings localized. |
| `DictusApp/Views/SwipeBackOverlayView.swift` | `VoxFlowiOS/Views/SwipeBackOverlayView.swift` | Copied/adapted | Cold-start return guidance localized for Mashangxie. |
| `DictusApp/Views/KeyboardModePicker.swift` | `VoxFlowiOS/Views/KeyboardModePicker.swift` | Copied/adapted | Default layer picker retained; preview labels localized. |
| `DictusApp/Onboarding/OnboardingView.swift` | `VoxFlowiOS/Onboarding/OnboardingView.swift` | Copied/adapted | Programmatic onboarding retained; model download step removed. |
| `DictusApp/Onboarding/WelcomePage.swift` | `VoxFlowiOS/Onboarding/WelcomePage.swift` | Copied/adapted | Brand/tagline changed to Mashangxie/码上写. |
| `DictusApp/Onboarding/MicPermissionPage.swift` | `VoxFlowiOS/Onboarding/MicPermissionPage.swift` | Copied/adapted | Uses system audio permission and explains main-app recording. |
| `DictusApp/Onboarding/KeyboardSetupPage.swift` | `VoxFlowiOS/Onboarding/KeyboardSetupPage.swift` | Copied/adapted | Detects `com.mashangxie.ios.keyboard`; simplified settings-card copy. |
| `DictusApp/Onboarding/ModeSelectionPage.swift` | `VoxFlowiOS/Onboarding/ModeSelectionPage.swift` | Copied/adapted | Keeps default keyboard layer selection; adds provider summary instead of model step. |
| `DictusApp/Onboarding/OnboardingSuccessView.swift` | `VoxFlowiOS/Onboarding/OnboardingSuccessView.swift` | Copied/adapted | Success animation retained; localized Mashangxie copy. |

### Dictus Phase 1 intentionally excluded

| Upstream path | Reason |
|---|---|
| `DictusApp/Audio/ParakeetEngine.swift` | Dictus model provider, not used by Mashangxie Phase 1. |
| `DictusApp/Audio/SpeechModelProtocol.swift` | Tied to Dictus local model abstraction. |
| `DictusApp/Audio/TranscriptionService.swift` | Shape used as reference only; replaced by existing `ASREngine` provider bridge. |
| `DictusApp/Models/ModelManager.swift` | Dictus model download/provider implementation is out of scope; local `ProviderModelAdapter.swift` preserves the public UI-facing shape and maps it to Mashangxie ASR providers. |
| `DictusApp/Onboarding/ModelDownloadPage.swift` | Dictus model download step is replaced by Mashangxie provider settings. |
| `DictusApp/Onboarding/GlobeKeyTutorialPage.swift` | Deferred; current Phase 1 setup covers keyboard enablement and cold-start guidance without test dictation tutorial. |
| `DictusWidgets/` | Future entry only; not Phase 1 blocking. |

### Hamster Phase 2 copy manifest

| Upstream path | Local path | Status | Purpose |
|---|---|---|---|
| `Packages/RimeKit/` | `ChineseInput/Upstream/RimeKit/` + `ChineseInput/RimeKitObjC/` | Copied/adapted as native boundary | Rime ObjC/C bridge and Hamster binary dependency route. `RimeKitObjC` exposes only the ObjC wrapper module to Swift so librime C headers do not leak into `ChineseInput`. |
| Hamster-compatible `Frameworks.tgz` native dependencies | `ChineseInput/Frameworks/` | Copied as native vendor baseline | Ten xcframeworks expected by RimeKit: `librime`, OpenCC, yaml-cpp, leveldb, marisa, glog, and Boost components. |
| `Packages/HamsterKeyboardKit/Sources/RimeContext/` | `ChineseInput/Upstream/HamsterKeyboardKit/Sources/RimeContext/` | Copied as upstream baseline | Candidate/preedit/commit state reference for the real Rime bridge. |
| `Packages/HamsterKit/Sources/T9/T9Constants.swift` | `ChineseInput/Upstream/HamsterKit/Sources/T9/T9Constants.swift` | Copied and compiled | 9-key digit mapping; wrapped by `ChineseInput/Sources/HamsterT9.swift`. |
| `Packages/HamsterKit/Sources/Extensions/String+.swift` T9 extension | `ChineseInput/Upstream/HamsterKit/Sources/Extensions_String+T9.swift` | Copied and compiled | Pinyin restoration helpers; wrapped by `ChineseInput/Sources/HamsterT9.swift`. |
| `Packages/HamsterKit/Sources/RimeSchema.swift` | `ChineseInput/Upstream/HamsterKit/Sources/RimeSchema.swift` | Copied and compiled | Schema model baseline. |
| `Packages/HamsterKit/Sources/Trie.swift` | `ChineseInput/Upstream/HamsterKit/Sources/Trie.swift` | Copied and compiled | T9 completion trie support. |
| `Packages/HamsterKeyboardKit/Sources/ChineseNineGridLayoutProvider.swift` | `ChineseInput/Upstream/HamsterKeyboardKit/Sources/ChineseNineGridLayoutProvider.swift` | Copied as upstream baseline | Chinese 9-key layout reference. |
| `Packages/HamsterKeyboardKit/Sources/iPhoneChineseKeyboardLayoutProvider.swift` | `ChineseInput/Upstream/HamsterKeyboardKit/Sources/iPhoneChineseKeyboardLayoutProvider.swift` | Copied as upstream baseline | Chinese 26-key layout reference. |
| `Packages/HamsterKeyboardKit/Sources/ChineseNineGridKeyboard.swift` | `ChineseInput/Upstream/HamsterKeyboardKit/Sources/ChineseNineGridKeyboard.swift` | Copied as upstream baseline | 9-key keyboard interaction reference. |
| `Resources/SharedSupport/hamster.yaml` | `ChineseInput/Upstream/Resources/SharedSupport/hamster.yaml` | Copied as upstream baseline | Hamster shared config reference. |
| Built-in schema resources | `ChineseInput/Resources/Schemas/` | Created and packaged | Built-in Rime Ice resource tree copied from `iDvel/rime-ice` at `846e5fcae56f0e3f4dcd8570319ffaf377e15471`. The 26-key route selects `rime_ice`; the 9-key route selects upstream `t9.schema.yaml`, which inherits `rime_ice` and applies T9 speller algebra. |

### Hamster / Rime native binary status

Hamster's `librimeFramework.sh` at commit
`65693706d01fc6c19ed6071968e542b0a2ef3f36` hardcodes:

```bash
LibrimeKitVersion="2.4.2"
curl -OL https://github.com/imfuxiao/LibrimeKit/releases/download/${LibrimeKitVersion}/Frameworks.tgz
```

Current validation on 2026-07-06:

- `https://github.com/imfuxiao/LibrimeKit/releases/download/2.4.2/Frameworks.tgz`
  returns HTTP 404.
- GitHub API for `imfuxiao/LibrimeKit` releases returns 404.
- `amorphobia/LibrimeKit` still exposes `v0.1.0/Frameworks.tgz` with the same
  xcframework names expected by Hamster's `Packages/RimeKit/Package.swift`.

Decision for this change set: copy the `amorphobia/LibrimeKit v0.1.0`
`Frameworks.tgz` artifacts into `ChineseInput/Frameworks/` as the available
Hamster-compatible fallback, and document the source in
`ChineseInput/Frameworks/SOURCE.md`.

Copied native dependencies:

- `boost_atomic.xcframework`
- `boost_filesystem.xcframework`
- `boost_regex.xcframework`
- `boost_system.xcframework`
- `libglog.xcframework`
- `libleveldb.xcframework`
- `libmarisa.xcframework`
- `libopencc.xcframework`
- `librime.xcframework`
- `libyaml-cpp.xcframework`

Important limitation: these artifacts are now present and each includes an iOS
arm64 device slice. `RimeKitObjC` links the copied RimeKit ObjC/C bridge plus
native vendor frameworks, and `ChineseInput` depends on that ObjC wrapper module
for the live `MashangxieKeyboard` extension path. Some libraries provide only
x86_64 simulator slices, so the iOS simulator build excludes arm64 and validates
the native path on x86_64. This is code/build/runtime evidence, not a substitute
for physical-device host-field validation.

### Rime native link probe status

`RimeNativeLinkProbe` is a dedicated extension-safe iOS framework target used to
validate the native dependency boundary without changing the current keyboard
runtime path. It compiles the copied Hamster ObjC/C bridge and links the copied
iOS arm64 static libraries with `APPLICATION_EXTENSION_API_ONLY=YES`.

Validated on 2026-07-06:

- `xcodegen generate` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme RimeNativeLinkProbe -destination 'generic/platform=iOS' build` succeeded.

The probe includes `ChineseInput/NativeProbe/RimeCompatibilityShim.c` because the
available `amorphobia/LibrimeKit v0.1.0` `librime_arm64.a` does not export the
newer `RimeReplaceInput` symbol declared by Hamster commit
`65693706d01fc6c19ed6071968e542b0a2ef3f36`. The shim returns `False` and exists
only to make the fallback vendor linkable while preserving the mismatch as an
explicit implementation fact. A production Rime bridge should either pin a newer
LibrimeKit asset that exports `RimeReplaceInput`, or keep this limitation in its
T9/replace-input behavior.

## 1.8 Upstream reference directories (read-only)

- `.codex/upstream-sources/dictus-ios/` — Dictus reference. DO NOT modify. DO NOT
  add as a submodule. Copy required files into `Apps/VoxFlowiOS/` and adapt.
- `.codex/upstream-sources/Hamster/` — Hamster reference. Same policy.

## 1.9 ASR provider frame format boundary

`UnifiedAudioEngine` normalizes microphone input to `VoxFlowAudio.AudioFrame`
before it reaches the existing provider engines:

- Sample rate: 16,000 Hz.
- Channels: mono.
- Sample representation: Float32 samples in `ContiguousArray<Float>`.
- `sequenceNumber`: monotonically increasing per recording session, reset when
  the engine state is purged.
- `startSample`: accumulated 16 kHz sample offset before the frame.
- `capturedAt`: `ContinuousClock.now` at frame emission time.

The keyboard extension never receives raw audio. Only the main app owns
`UnifiedAudioEngine` and provider runtime dependencies.

## 1.10 Current Phase 1 static / simulator validation

Validated on 2026-07-06:

- `xcodegen generate` from `Apps/VoxFlowiOS/` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme Mashangxie -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme MashangxieKeyboard -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme SharedTests -configuration Debug -destination 'platform=iOS Simulator,id=7D74D73C-D37A-4F7E-8540-0D060EB49B85' CODE_SIGNING_ALLOWED=NO test` succeeded with 15 tests and 0 failures.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme KeyboardTests -configuration Debug -destination 'platform=iOS Simulator,id=6345B5C8-7416-4499-8472-7DE02BA68406' CODE_SIGNING_ALLOWED=NO test` succeeded with 10 tests and 0 failures.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme MashangxieTests -configuration Debug -destination 'platform=iOS Simulator,id=7D74D73C-D37A-4F7E-8540-0D060EB49B85' CODE_SIGNING_ALLOWED=NO test` succeeded with 6 tests and 0 failures.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme ChineseInputTests -configuration Debug -destination 'platform=iOS Simulator,id=6345B5C8-7416-4499-8472-7DE02BA68406' CODE_SIGNING_ALLOWED=NO test` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme RimeNativeLinkProbe -destination 'generic/platform=iOS' build` succeeded with `APPLICATION_EXTENSION_API_ONLY=YES`.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme RimeNativeRuntimeTests -destination 'platform=iOS Simulator,arch=x86_64,id=6345B5C8-7416-4499-8472-7DE02BA68406' test` succeeded and validated native Rime candidates for `6464` and `94664`.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme MashangxieKeyboard -destination 'platform=iOS Simulator,arch=x86_64,id=6345B5C8-7416-4499-8472-7DE02BA68406' build` succeeded after wiring `NativeChineseRimeBridge` into the keyboard extension.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme MashangxieKeyboard -destination 'generic/platform=iOS' build` succeeded after wiring `NativeChineseRimeBridge` into the keyboard extension.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme Mashangxie -destination 'platform=iOS Simulator,arch=x86_64,id=6345B5C8-7416-4499-8472-7DE02BA68406' build` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme Mashangxie -destination 'generic/platform=iOS' build` succeeded.
- `xcodebuild -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme ChineseInputTests -destination 'platform=iOS Simulator,arch=x86_64,id=6345B5C8-7416-4499-8472-7DE02BA68406' test` succeeded and includes `NativeChineseRimeBridge` T9 candidate coverage.
- `xcodebuild -quiet -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme MashangxieTests -destination 'platform=iOS Simulator,arch=x86_64,id=6345B5C8-7416-4499-8472-7DE02BA68406' test` succeeded and now covers the ASR bridge plus packaging contracts for app Info.plist, keyboard Info.plist, App Group entitlements, embedded extension, URL scheme, copied-target Swift 5 boundary, and keyboard/provider dependency boundaries.
- `xcodebuild -quiet -project Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj -scheme MashangxieTests -destination 'platform=iOS Simulator,arch=x86_64,id=6345B5C8-7416-4499-8472-7DE02BA68406' -only-testing:MashangxieTests/MashangxiePackagingContractTests test` succeeded after adding the Swift boundary assertions.
- `make ios-test-sim` succeeded after the Dictus Models/Settings/Home UI was moved back to copied source structure with `ProviderModelAdapter` as the only model-layer replacement.
- `make ios-run-sim` built and launched `com.mashangxie.ios` on `iPhone 16, iOS 18.5`.
- Simulator manual app check on 2026-07-06 verified the Dictus-style Home dashboard, Models/Provider card list, grouped Settings screen, and full-screen recording overlay. Starting/stopping Apple Speech dictation did not crash; the simulator produced `[preparationFailed] No speech detected`, which is expected without a real spoken input path.
- Simulator manual app check also verified that an active cloud provider without user/dev credentials no longer appears as ready; the copied Dictus Models card shows the missing-credential retry/error state instead.
- Simulator manual app check on 2026-07-06 re-verified the copied Dictus Models full-screen preparation overlay after `RecordingView`, `ModelLoadingOverlay`, `CyclingLoadingText`, and `SwipeBackOverlayView` were restored to upstream structure. Selecting Apple Speech from Available showed the Dictus waveform/checkmark completion overlay and dismissed automatically; only the model/provider boundary is adapted by `ProviderModelAdapter`.
- Dev credential injection was verified with a canary `MASHANGXIE_DEV_ALIYUN_API_KEY`; `make ios-build-sim` succeeded, and the build log did not contain the canary plaintext, its base64 value, old `MASHANGXIE_DEV_*_B64` build settings, or `-xcconfig`.
- Crash-risk audit checked the copied app/keyboard/Chinese input code for high-risk forced operations. The actionable app-side `try!` in `iOSAudioRecorder` converter setup was removed; remaining `fatalError(init(coder:))` and fixed array indexing hits are in copied UIKit/vendor/upstream code paths and are tracked as copied-code risk rather than rewritten in Phase 1.
- A local check of `~/Library/Logs/DiagnosticReports` found no Mashangxie/VoxFlowiOS crash report from the simulator run.
- `make i18n-check` from the repository root succeeded. That root check covers the macOS app and ScreenshotKit resources.
- `plutil -lint` succeeded for all iOS App and Keyboard `Localizable.strings`, Info.plist, and entitlements files.
- iOS App and Keyboard five-language `Localizable.strings` key parity was checked with `plutil -convert json` + `jq` + `diff`; no key differences were reported.
- `Apps/VoxFlowiOS/Scripts/verify-device-prereqs.sh --no-build` regenerated the Xcode project, listed devices, and exited with status 2 because no online physical iPhone/iPad was available.
- `Apps/VoxFlowiOS/Scripts/verify-device-prereqs.sh` regenerated the Xcode project, completed the generic iOS App/Keyboard builds, listed devices, and exited with status 2 for the same no-online-device blocker.
- `xcrun xctrace list devices` showed the only physical device entry available
  to this machine as offline (`XiaoMi SU7 (26.5)`), so device install and WeChat
  validation could not be executed in this run.
- `openspec validate build-mashangxie-ios-keyboard --strict` succeeded.

Root Makefile entry points for this iOS work now target the current Mashangxie
App + Keyboard Extension shape:

```bash
make ios-gen-project
make ios-build-sim
make ios-run-sim
make ios-test-sim
make ios-device-preflight
```

The default simulator target is `iPhone 16`, `OS=18.5`, `arch=x86_64`, matching
the current Rime simulator dependency constraints. Override with
`IOS_SIMULATOR_NAME`, `IOS_SIMULATOR_OS`, or `IOS_SIMULATOR_ARCH` when needed.
These Makefile targets are static/simulator checks only; they do not replace the
physical-device WeChat validation in section 1.13.

Dev cloud credentials can be baked into a local dev build from environment
variables while keeping the in-app manual credential UI available:

```bash
MASHANGXIE_DEV_TENCENT_APP_ID=... \
MASHANGXIE_DEV_TENCENT_SECRET_ID=... \
MASHANGXIE_DEV_TENCENT_SECRET_KEY=... \
MASHANGXIE_DEV_ALIYUN_API_KEY=... \
MASHANGXIE_DEV_VOLCENGINE_APP_ID=... \
MASHANGXIE_DEV_VOLCENGINE_ACCESS_TOKEN=... \
MASHANGXIE_DEV_VOLCENGINE_SECRET_KEY=... \
make ios-run-sim
```

`make ios-gen-project`, `make ios-build-sim`, and `make ios-build-device`
generate `Apps/VoxFlowiOS/Generated/DevCloudCredentials.plist` before XcodeGen
runs. That file is gitignored and is packaged as an app resource. The app reads
manual credentials first; if a provider's manual values are incomplete, it falls
back to this generated dev resource. This intentionally avoids `-xcconfig`
credential injection because Xcode prints xcconfig build settings in build logs.

The Xcode post-build phase also copies this generated plist into the app bundle.
`Scripts/write-dev-cloud-resource.py` preserves an existing generated plist when
the post-build environment has no `MASHANGXIE_DEV_*` variables at all. This
prevents Xcode from overwriting Makefile-generated dev credentials with empty
values. To intentionally clear dev credentials, run the script or Makefile path
with the `MASHANGXIE_DEV_*` variables explicitly present and empty.

Verified by build/static checks:

- The main app target embeds `MashangxieKeyboard.appex`.
- The keyboard target links `Shared` and `DeviceKit`; it does not link the ASR
  runtime or cloud provider targets directly.
- The main app target owns the ASR provider bridge and links existing provider
  targets.
- `MashangxiePackagingContractTests` locks the key install-time contracts:
  `com.mashangxie.ios`, `com.mashangxie.ios.keyboard`,
  `group.com.mashangxie.ios`, `mashangxie://`, `RequestsOpenAccess=true`, and
  `PrimaryLanguage=zh-Hans`. It also locks the Swift version boundary: the app and
  provider bridge stay on the project Swift 6 default, while copied
  Keyboard/Shared/ChineseInput layers stay on Swift 5 with minimal strict
  concurrency.
- Phase 1 builds do not require Dictus WhisperKit, Parakeet, Dictus model
  downloads, or Dictus French local model assets.
- The app entry now uses `MainTabView`, a Dictus-style shell with copied
  `RecordingView` and cold-start `SwipeBackOverlayView` structures.
- The Models tab now uses copied Dictus `ModelManagerView` / `ModelCardView` /
  `GaugeBarView` / `ModelLoadingOverlay` / `CyclingLoadingText`;
  `ProviderModelAdapter` is the boundary that converts Dictus model concepts into
  Apple Speech, Tencent Cloud, Aliyun DashScope, and Volcengine providers.
- Settings now uses copied Dictus grouped settings surfaces with localized
  Mashangxie strings, diagnostics/debug logs, keyboard preview, sound settings,
  and log export.
- The previous `RootTabView` / `DictationView` / `ServiceManagerView`
  feasibility UI has been deleted so the app UI path stays on copied Dictus
  surfaces.
- `DictationCoordinator` now uses copied `UnifiedAudioEngine`, not
  `iOSAudioRecorder`, on the keyboard dictation path.
- `KeyboardTests` covers `KeyboardState` requested-state fallback URL behavior,
  shared transcription clearing, stop/cancel flags, and the current Chinese
  26-key / 9-key layout host points without changing the copied Dictus shell shape.
  It also covers the Chinese 26-key -> English and English -> Chinese 26-key
  alternate-key bridge, plus voice-entry ordering from Chinese 26-key and
  Chinese 9-key modes: composition preflight runs before the copied Dictus
  recording state is started.
- `MashangxieTests` covers the ASR provider bridge for provider/language engine
  creation, audio-frame forwarding, partial/final callbacks, stop/cancel/endAudio,
  unavailable provider, missing credentials, and error callback mapping.
- `ChineseInputTests` covers Hamster T9 examples (`64`, `646`, `6464`, `94664`),
  pinyin-to-digit restoration, Chinese 9-key row shape, schema resource packaging,
  deployment-directory planning, and copying built-in schema resources into both
  App Group and sandbox SharedSupport directories. It also covers the
  Rime-shaped bridge/session state transitions for preedit, candidates, commit,
  delete-before-host-text, mode switching, and voice preflight policy. It now also
  verifies that the Rime native vendor directory contains every expected
  xcframework and that each one includes an iOS arm64 device slice. The
  x86_64 simulator run additionally starts `NativeChineseRimeBridge` and verifies
  that the live bridge can produce native T9 candidates for `6464`, switch from
  the pinyin schema to the T9 schema, and reuse the process-level Rime deploy
  without redeploying per keyboard controller/session.
- `RimeNativeLinkProbe` verifies that the copied Hamster ObjC/C Rime bridge can
  link the copied native Rime vendor libraries for a generic iOS device under
  extension-safe build settings.
- `RimeNativeRuntimeTests` runs the copied Hamster ObjC/C Rime bridge against the
  bundled schema resources on the x86_64 iOS simulator slice, deploys Rime, opens
  the built-in `t9` schema, and verifies candidate paths for `6464` (`明` / `宁`)
  and `94664` (`中` / `熊`).
- App visible strings added for the copied App UI are present in all five app
  localization resource sets.

Not yet verified:

- Physical iPhone installation with valid signing.
- Manual keyboard enablement in iOS Settings.
- WeChat insertion through the real third-party Keyboard Extension.
- Warm-path vs cold-start behavior on device.
- AltStore / SideStore feasibility.
- `textDocumentProxy.insertText` can only be formally verified inside a real host
  text field; simulator/unit tests cover the surrounding shared-state cleanup and
  fallback protocol.
- Real native Rime preedit/commit inside a physical host text field. Current
  Phase 2 work has copied Hamster slices, packaged minimal schema resources,
  copied Hamster-compatible native Rime vendor frameworks, verified
  extension-safe iOS device linking, verified native T9 candidate paths on
  x86_64 simulator, and wired `NativeChineseRimeBridge` into the live
  `MashangxieKeyboard` code path, but it still needs device validation in a
  real third-party keyboard session.

Residual simulator warnings:

- Copied keyboard code still emits an iOS 17 deprecation warning for
  `traitCollectionDidChange`.
- Copied AOSP trie bridge code still emits always-succeeds `[String] as? [String]`
  cast warnings.
- Copied Hamster RimeKit ObjC/C code emits upstream C/header warnings
  (`deprecated` documentation attributes, strict prototypes, and a
  `processKey` pointer/integer warning in copied code). Swift's implicit
  bridging-header import warning was removed by splitting the native bridge into
  `RimeKitObjC`; `ChineseInput` now imports the ObjC wrapper module instead of
  exposing a Swift bridging header. The probe target no longer defines a module,
  so it also avoids the previous no-umbrella-header warning.
- iOS simulator builds exclude arm64 because several fallback LibrimeKit
  xcframeworks only ship x86_64 simulator slices. Generic iOS device builds still
  use the arm64 device slices.
- These warnings did not fail the targeted simulator tests. They are tracked as
  copied-code cleanup candidates rather than Phase 1/Phase 2 acceptance blockers.

## 1.11 Phase 1 current directory tree

```text
Apps/VoxFlowiOS/
  project.yml
  NOTES.md
  THIRD_PARTY_NOTICES.md
  Keyboard/
    KeyboardViewController.swift
    KeyboardState.swift
    KeyboardRootView.swift
    KeyboardLayouts.swift
    KeyboardMetrics.swift
    InputView.swift
    DictusKeyboardBridge.swift
    KeyboardVoiceEntryCoordinator.swift
    DictusKeyboard-Bridging-Header.h
    Info.plist
    Keyboard.entitlements
    Models/
    Views/
    TextPrediction/
    TouchHandling/
    Vendored/
    Resources/
  Shared/
    AppGroup.swift
    SharedKeys.swift
    SharedStatusStore.swift
    DarwinNotifications.swift
    DictationStatus.swift
    Design/
    Languages/
    TextCorrection/
  SharedTests/
    SharedStatusStoreTests.swift
  KeyboardTests/
    KeyboardStateTests.swift
    ChineseKeyboardLayoutTests.swift
    ChineseKeyboardModeSwitchTests.swift
    KeyboardVoiceEntryCoordinatorTests.swift
  MashangxieTests/
    ASRBridgeTests.swift
  ChineseInput/
    Sources/
      ChineseInputMode.swift
      ChineseInputSession.swift
      HamsterT9.swift
      RimeBridge.swift
      RimeNativeDependencyManifest.swift
      RimeSchemaDeployment.swift
    NativeProbe/
      RimeCompatibilityShim.c
    Resources/
      Schemas/
        default.yaml
        rime_ice.schema.yaml
        rime_ice.dict.yaml
        t9.schema.yaml
        cn_dicts/
        en_dicts/
        lua/
        opencc/
    Frameworks/
      SOURCE.md
      boost_atomic.xcframework/
      boost_filesystem.xcframework/
      boost_regex.xcframework/
      boost_system.xcframework/
      libglog.xcframework/
      libleveldb.xcframework/
      libmarisa.xcframework/
      libopencc.xcframework/
      librime.xcframework/
      libyaml-cpp.xcframework/
    RimeKitObjC/
      RimeKitObjC.h
      module.modulemap
    Upstream/
      RimeKit/
      HamsterKit/
        Sources/
          T9/T9Constants.swift
          Extensions_String+T9.swift
          RimeSchema.swift
          Trie.swift
      HamsterKeyboardKit/
        Sources/
          RimeContext/
          ChineseNineGridKeyboard.swift
          ChineseNineGridLayoutProvider.swift
          iPhoneChineseKeyboardLayoutProvider.swift
      Resources/
        SharedSupport/hamster.yaml
  ChineseInputTests/
    ChineseInputTests.swift
  RimeNativeLinkProbe
    (Xcode target only; sources live under ChineseInput/Upstream/RimeKit and ChineseInput/NativeProbe)
  RimeNativeRuntimeTests/
    RimeNativeRuntimeTests.m
  VoxFlowiOS/
    VoxFlowiOSApp.swift
    AppState.swift
    Info.plist
    Mashangxie.entitlements
    AppleSpeechASREngineAdapter.swift
    iOSASREngineFactory.swift
    LocalCredentialStore.swift
    iOSAudioRecorder.swift
    Audio/
      UnifiedAudioEngine.swift
      ObjCExceptionCatcher.h
      ObjCExceptionCatcher.m
    Dictation/
      DictationCoordinator.swift
      ASRBridge.swift
      DictusApp-Bridging-Header.h
    Views/
      MainTabView.swift
      HomeView.swift
      RecordingView.swift
      SwipeBackOverlayView.swift
      ModelManagerView.swift
      ModelCardView.swift
      ModelLoadingOverlay.swift
      CyclingLoadingText.swift
      GaugeBarView.swift
      KeyboardModePicker.swift
      DiagnosticsView.swift
      SettingsView.swift
      SoundSettingsView.swift
      LicensesView.swift
      DebugLogView.swift
    Onboarding/
      OnboardingView.swift
      WelcomePage.swift
      MicPermissionPage.swift
      KeyboardSetupPage.swift
      ModeSelectionPage.swift
      OnboardingSuccessView.swift
      OnboardingPrimaryButton.swift
    Resources/
      en.lproj/Localizable.strings
      zh-Hans.lproj/Localizable.strings
      zh-Hant.lproj/Localizable.strings
      ja.lproj/Localizable.strings
      ko.lproj/Localizable.strings
```

Current Phase 2 status: the `ChineseInput` target exists and is wired into the
keyboard extension. It compiles the Hamster T9/layout/schema scaffolding and
`NativeChineseRimeBridge`; `RimeKitObjC` compiles the copied RimeKit ObjC/C
bridge and links the native vendor frameworks. `KeyboardViewController` creates a
`NativeChineseRimeBridge`/`ChineseInputSession` pair and injects it into the
copied Dictus key bridge. `RimeNativeLinkProbe` proves the copied Hamster ObjC/C
bridge and native libraries link for generic iOS device builds under
extension-safe settings, while `ChineseInputTests` proves the injected native
bridge can produce T9 candidates and switch pinyin -> T9 schema on the x86_64
simulator path. Physical-device host-field validation is still required before
Phase 2 can be called complete.

## 1.12a Current Chinese input bridge status

The Dictus keyboard shell now has a Chinese composition bridge point:

- `ChineseInputSession` owns `ChineseInputState` and talks only to the
  `ChineseRimeBridge` protocol.
- `ChineseRimeBridge` exposes the Rime-shaped state needed by the keyboard:
  preedit, candidate list, selected candidate commit text, delete, reset, start,
  and Chinese 26-key / 9-key schema switching.
- `ChineseRimeBridge` and `NativeChineseRimeBridge` are `@MainActor`. The copied
  Dictus keyboard path already drives composition changes from the main actor,
  and making this explicit keeps the Rime C API session serialized instead of
  relying on convention.
- `NativeChineseRimeBridge` treats librime setup/deploy as process-level work:
  setup/deploy runs once per keyboard extension process, while subsequent
  `KeyboardViewController` instances create their own Rime sessions. This matches
  iOS's tendency to cache/recreate keyboard controllers without assuming librime
  can safely redeploy from multiple data directories in one process.
- `KeyboardViewController` injects a `NativeChineseRimeBridge`-backed
  `ChineseInputSession` into `DictusKeyboardBridge`.
- `DictusKeyboardBridge` routes Chinese 26-key letters and 9-key digits into
  `ChineseInputSession` when the session starts successfully.
- The copied Dictus keyboard layout now has explicit Chinese 26-key, Chinese
  9-key/T9, English, symbols/numbers, emoji, and voice-entry paths. The Chinese
  26-key bottom row exposes `九键` and `EN`; the English bottom row exposes
  `中文` while keeping the emoji, space, and return keys.
- Voice entry from Chinese modes now goes through `KeyboardVoiceEntryCoordinator`:
  it awaits Chinese composition preflight and then starts the existing copied
  Dictus `KeyboardState.startRecording()` path.
- Rime candidates returned by the bridge are rendered in the existing Dictus
  suggestion bar location via `SuggestionMode.chineseCandidates`.
- Candidate taps call back into the Chinese session and commit through
  `textDocumentProxy.insertText`.
- Backspace deletes composition before host text when composition is active.
- Space commits the default candidate when composition is active.
- Starting voice dictation first applies the configured composition policy. The
  current default is `commitBeforeVoice`, matching a conservative keyboard UX:
  preserve user-entered composition as committed text before the Dictus recording
  overlay starts.

This is now a live-code bridge/session path backed by the copied Hamster RimeKit
ObjC/C runtime. The remaining gap is not "no native bridge"; it is real
third-party keyboard validation in a host text field on device, including Chinese
26-key preedit/commit, 9-key/T9 preedit/commit, deletion, mode switching, and
voice coexistence.

## 1.12 Phase 2 Chinese input verification sequences

These are the acceptance sequences for the Hamster/Rime phase. They are not
Phase 1 checks.

### Default Chinese 26-key

1. Install the app and enable the Mashangxie keyboard on a physical iPhone.
2. Open WeChat or another host app with a real text field.
3. Switch to Mashangxie.
4. Verify the initial layout is Chinese 26-key, not English ABC.
5. Type `nihao`.
6. Verify Rime preedit/composition appears and candidates are rendered in the
   Dictus-style candidate bar position.
7. Select `你好` or the best available default candidate.
8. Verify the committed Chinese text is inserted through `textDocumentProxy`.
9. Type another pinyin sequence, press delete while composition is active, and
   verify deletion edits composition before host-app text.
10. Press space/commit on a candidate and verify composition clears after commit.

### Chinese 9-key / T9

1. From the Chinese 26-key layout, switch to Chinese 9-key/T9.
2. Verify keys use Hamster-style groups: `ABC`, `DEF`, `GHI`, `JKL`, `MNO`,
   `PQRS`, `TUV`, `WXYZ`.
3. Enter `6464`.
4. Verify the copied T9 path maps to pinyin options such as `ming` / `ning` where
   the bundled schema supports them, and Rime returns Chinese candidates.
5. Select a candidate and verify text is inserted into the host input field.
6. Enter `94664` and verify candidate paths for `xiong` / `zhong` where supported.
7. Test clear-composition, delete, return, symbol, numeric, space, and 26-key
   switch actions against the Hamster mapping.

### Mode switching and voice coexistence

1. Switch among Chinese 26-key, Chinese 9-key/T9, English, symbols/numbers, emoji,
   and voice entry.
2. Verify candidate/preedit state is cleared, committed, or preserved according
   to the selected Hamster/Rime behavior.
3. Start voice dictation from Chinese 26-key.
4. Verify the Dictus-style recording overlay and waveform still appear.
5. Stop recording and verify final ASR text inserts through the existing Phase 1
   App Group / keyboard insertion path.
6. Repeat from Chinese 9-key/T9.
7. Start voice while Chinese composition is active and verify the defined behavior
   does not leave the Rime composition in an inconsistent state.

## 1.13 Manual WeChat validation script

Use this script once physical-device signing is available.

### Distribution modes

The iOS project keeps one App + Keyboard Extension code path and separates only
the packaging/signing entry points:

```bash
make ios-ipa
```

This creates `dist/ios/Mashangxie.ipa`. The package is unsigned and must be
signed before installing on a physical device. The build verifies that the IPA contains
`Payload/Mashangxie.app/PlugIns/MashangxieKeyboard.appex`, the Chinese input
runtime frameworks, and the source App Group entitlements. A successful package
check does not prove runtime App Group authorization after signing; use the app
diagnostics App Group rows on the physical device.

```bash
MASHANGXIE_DEVELOPMENT_TEAM=<team-id> make ios-keyboard-release-archive
```

This is the future paid-developer/TestFlight/App Store-compatible archive path.
It uses the same identifiers (`com.mashangxie.ios`,
`com.mashangxie.ios.keyboard`, `group.com.mashangxie.ios`) and does not require
source changes when switching from free probing to paid signing.

Before starting, run the preflight helper from the repository root:

```bash
Apps/VoxFlowiOS/Scripts/verify-device-prereqs.sh
```

If an online physical device and signing team are available, an optional signed
device build can be attempted with:

```bash
MASHANGXIE_DEVICE_UDID=<device-udid> \
MASHANGXIE_DEVELOPMENT_TEAM=<team-id> \
Apps/VoxFlowiOS/Scripts/verify-device-prereqs.sh --device-build
```

The preflight helper is not a substitute for the WeChat acceptance flow. It only
rebuilds the Xcode project, verifies generic iOS App/Keyboard builds, lists
available devices, and reports when validation remains blocked by missing online
hardware or signing inputs.

1. Install `Mashangxie.app` with embedded `MashangxieKeyboard.appex` on a physical
   iPhone.
2. Open iOS Settings > General > Keyboard > Keyboards > Add New Keyboard and add
   Mashangxie.
3. Enable Full Access for Mashangxie if using cloud providers or App Group behavior
   that requires it.
4. Open Mashangxie once, choose Apple Speech or configure cloud provider credentials,
   and confirm the app home shows provider ready.
5. Warm path:
   - Keep Mashangxie alive.
   - Open WeChat.
   - Focus a chat input field.
   - Switch to the Mashangxie keyboard.
   - Tap the voice button.
   - Speak a short Chinese phrase.
   - Stop from the keyboard.
   - Verify final text appears in the WeChat input field via keyboard insertion.
6. Cold-start path:
   - Force-quit or background Mashangxie until the keyboard cannot get a warm
     response.
   - In WeChat, focus the input field and tap voice from the Mashangxie keyboard.
   - Verify the keyboard opens `mashangxie://dictate?source=keyboard`.
   - Verify the app shows the cold-start return overlay while recording begins.
   - Return to WeChat and verify the final text is inserted by the keyboard.
7. Stop/cancel:
   - Start recording from the keyboard.
   - Test stop and cancel separately.
   - Verify shared status returns to idle/ready/failed as expected and no stale
     transcription is inserted twice.
8. Record the validation mode explicitly: paid developer signing, local Xcode
   signing, AltStore/SideStore probe, simulator, mock, or static check.

## 1.14 License attribution

Repository-visible license attribution for copied/planned upstream code is kept
in `Apps/VoxFlowiOS/THIRD_PARTY_NOTICES.md`. Do not rely on
`.codex/upstream-sources/` for license compliance because that directory is
reference-only and gitignored.

These directories are gitignored from the main project history and exist only to
make the gold-standard source available during the change.

## 1.15 2026-07-06 simulator revalidation notes

Swift boundary:

- The copied Dictus/Hamster keyboard, shared, and Chinese input targets remain on
  Swift 5 with minimal strict concurrency. This is intentional and scoped to the
  copied extension-safe source boundary.
- The main Mashangxie app and ASR provider bridge remain on the project Swift 6
  setting. This is not a global Swift downgrade.

Cloud provider configuration:

- `DevCloudCredentials` now has a test seam for decoding generated plist payloads.
- `LocalCredentialStore` now defaults to the App Group file container rather than
  the main-app sandbox. On first use it migrates a non-empty legacy sandbox
  `Application Support/VoxFlow/credentials.json` into the shared location without
  overwriting an existing shared credential file. This keeps provider selection
  and provider credentials in the same cross-process storage boundary.
- `LocalCredentialStore.effectiveValues` still prefers complete user-entered
  credentials and falls back to the generated dev resource only when manual
  credentials are incomplete.
- `ASRBridgeTests.testConfiguredCloudProvidersBuildAvailableEngines` verifies
  that Tencent, Aliyun, and Volcengine all build available `ASREngine`s from
  complete local credential values. This covers field names, credential-store
  lookup, and factory readiness without making a live network request.
- A canary run of `Scripts/write-dev-cloud-resource.py` decoded all seven
  Tencent, Aliyun, and Volcengine fields without printing secret values.
- A full `make ios-build-sim` canary with fake Tencent, Aliyun, and Volcengine
  values verified that the final `Mashangxie.app/DevCloudCredentials.plist`
  keeps those values after Xcode's post-build copy phase. This covers the
  previously risky path where Xcode could re-run the script without the
  `MASHANGXIE_DEV_*` environment and silently package empty credentials.
- The current repository environment does not define the
  `MASHANGXIE_DEV_*` cloud variables, so the generated
  `DevCloudCredentials.plist` in this pass intentionally contains empty values.
  Real dev-key validation requires setting those environment variables before
  `make ios-run-sim` / `make ios-test-sim`.
- Simulator configured-state smoke check:
  - Before writing a dummy Tencent credential file, Home showed Tencent as
    missing credentials.
  - After writing the same JSON path used by `LocalCredentialStore` inside the
    simulator app container and relaunching, Home showed Tencent Cloud ASR as
    ready and displayed the Start Dictation button.
  - This validates local credential storage/readiness and provider factory
    configuration gating. It does not validate a live cloud ASR request because
    the simulator used dummy credentials.

Keyboard typing:

- Root cause found for the grey keyboard shell observed in simulator: an earlier
  `MashangxieKeyboard` crash report terminated at dyld launch with
  `Library not loaded: @rpath/ChineseInput.framework/ChineseInput`. That means
  iOS selected the keyboard slot, but the extension process died before
  `KeyboardViewController` could render the copied Dictus/Hamster UI.
- The currently installed simulator bundle was rechecked after `make ios-run-sim`:
  `PlugIns/MashangxieKeyboard.appex/Frameworks/ChineseInput.framework` and
  `RimeKitObjC.framework` are present, and `otool -L` on
  `MashangxieKeyboard.debug.dylib` resolves both `@rpath` dependencies.
- `MashangxiePackagingContractTests.testBuiltKeyboardExtensionEmbedsChineseInputRuntimeFrameworks`
  now verifies those frameworks in the built app bundle so the dyld failure
  cannot silently regress.
- No newer `MashangxieKeyboard` crash report appeared after reinstalling the
  current simulator build. This proves the previous dyld packaging issue is no
  longer present in the installed bundle, but it does not by itself prove
  host-field typing because switching into the third-party keyboard still needs
  the system globe interaction.
- `DictusKeyboardBridge` now falls back to inserting the raw key text if the
  Chinese Rime session is already started but `input(_:)` throws. This prevents a
  broken Rime runtime from making the keyboard appear alive while swallowing
  typed keys.
- `DictusKeyboardBridge` also falls back to raw key insertion when Rime accepts a
  key but returns an empty composition with no preedit, candidates, or commit
  text. This covers the "started but inert" failure mode observed while probing
  live keyboard typing.
- `KeyboardTests.testChineseInputFailureFallsBackToRawHostText` covers this path
  with a fake `UITextDocumentProxy` and a throwing `ChineseRimeBridge`.
- `KeyboardTests.testChineseInputEmptyCompositionFallsBackToRawHostText` covers
  the empty-composition fallback path.
- `KeyboardTests.testChineseQwertyCandidateTapCommitsTextToHostProxy` and
  `KeyboardTests.testChineseNineGridCandidateTapCommitsTextToHostProxy` cover
  the successful 26-key and 9-key/T9 commit paths with a fake host
  `UITextDocumentProxy`. These prove the bridge calls `insertText` after a
  candidate tap.
- Safari host-field autofocus was validated in simulator at
  `http://127.0.0.1:8765/`; the system keyboard appeared correctly.
- The Mashangxie keyboard was present in
  `com.apple.keyboard.preferences.plist`. Earlier Mac-window automation could not
  inject the long-press globe gesture, so a dedicated UI-test host app route was
  added instead.
- `MASHANGXIE_RUN_KEYBOARD_SWITCH_UI_TEST=1 make ios-ui-test-sim` now switches
  from the system keyboard into the real Mashangxie keyboard extension, verifies
  Mashangxie-only keys are visible, commits `你` from 26-key pinyin, switches to
  9-key, enters `6464`, and commits a T9 candidate into the host text view.
- The same opt-in UI test now also validates Chinese 26-key -> English ->
  symbols/numbers -> letters -> Chinese switching, then taps the keyboard
  microphone while `ni` is still composing and verifies the active Chinese
  candidate is committed into the host text view before recording starts.
- A test-only host launch argument can simulate app-side final transcription
  delivery. The opt-in UI test uses it to verify the real keyboard extension
  handles Rime -> voice -> `transcriptionReady` -> `textDocumentProxy.insertText`
  and leaves `你语音` in the host text view. This validates insertion after Rime
  without depending on live microphone input or a real cloud ASR request.
- Full physical-device WeChat validation remains a separate Phase 9 step.

Verification commands:

```bash
make ios-test-sim
MASHANGXIE_RUN_KEYBOARD_SWITCH_UI_TEST=1 make ios-ui-test-sim
make ios-build-sim
```

Additional dev credential canary:

```bash
MASHANGXIE_DEV_TENCENT_APP_ID=... \
MASHANGXIE_DEV_TENCENT_SECRET_ID=... \
MASHANGXIE_DEV_TENCENT_SECRET_KEY=... \
MASHANGXIE_DEV_ALIYUN_API_KEY=... \
MASHANGXIE_DEV_VOLCENGINE_APP_ID=... \
MASHANGXIE_DEV_VOLCENGINE_ACCESS_TOKEN=... \
MASHANGXIE_DEV_VOLCENGINE_SECRET_KEY=... \
make ios-build-sim
```

This pass verified all seven generated plist fields were packaged and the canary
plaintext values were absent from the captured build log. The local generated
plist was then reset to empty because no real `MASHANGXIE_DEV_*` variables are
present in the current shell.

Both completed successfully in this pass. Xcode emitted non-fatal
`LogStoreManifest.plist` result-bundle messages during tests.

## 1.16 Candidate capability & reliability pass (2026-07-07 → reworked 2026-07-08)

Scope: fix five architectural defects in the v1 pass that (a) flattened `CandidateSuggestion`
metadata to `[String]`, (b) permanently degraded Chinese input to raw latin on Rime failure,
(c) left the startup hot path unbundled, and (d) lacked hash/length verification in the
clipboard bridge.

**1. Candidate metadata preserved end-to-end.**
- `SuggestionState` now stores `chineseCandidates: [CandidateSuggestion]` alongside
  `suggestions: [String]`. `updateChineseComposition` takes `[CandidateSuggestion]`.
- `DictusKeyboardBridge.applyChineseInputAction(.updateComposition)` passes typed
  candidates; display titles are in `suggestions`, Rime `index` is used for selection.
- `KeyboardRootView.handleSuggestionTap` looks up `chineseCandidates[visibleIndex].index`
  to call `handleChineseCandidateTap(index:)` with the correct Rime global index.
- `SuggestionBarView`/`ToolbarView` display pipeline uses `[String]` for English and
  `toolbarSuggestions` (mapped from typed candidates) for Chinese. The typed list is
  available to the expanded panel for future paging/pinyin-column use.

**2. Rime failure does not permanently degrade to raw input.**
- Removed the `chineseInputStatus == .failed` fast-path in `handleChineseInput` that
  called `insertRawFallback`. Removed the error-catch block that inserted raw host text.
- `handleChineseInput` when `input(_:)` throws: re-buffers the key and keeps the
  suggestion bar in preedit state. No host text is inserted.
- `handleChineseInputSessionFailed` and `setChineseInputStatus(.failed)`: clear the
  buffer without inserting raw text. The toolbar shows the failure message; the user
  can switch to English mode or wait for retry.
- Retry count raised from 1→5 with exponential backoff (0.25s/0.5s/1s/2s/4s). Only
  after the 5th failure is `.failed` terminal and the session permanently cleared.
- `ThrowingInputChineseRimeBridge` test fake added for validating the no-raw-fallback
  behavior.

**3. Pre-warm Chinese session in viewDidLoad.**
- `KeyboardViewController.prewarmChineseInputSession()` kicks off `installChineseInputSession`
  during the keyboard entry animation (before the keyboard is visible to the user), so
  the Rime deploy cost is amortized before the first keystroke.
- The existing `onChineseInputNeeded` → `installChineseInputSession` path remains as
  the fallback if `viewDidLoad` pre-warming fails.

**4. Clipboard exact-text reliability.**
- Write side (`ClipboardDictationHandoffView`): computes SHA-256 hash; records
  `UIPasteboard.changeCount` before/after write; stores `clipboardTextHash`,
  `clipboardTextLength`, and `clipboardWriteChangeCount` via App Group; verifies
  by immediate read-back with one retry after 100ms.
- Read side (`KeyboardState.readPasteboardIfPending`): no longer trims with
  `.trimmingCharacters(in: .whitespacesAndNewlines)`; computes SHA-256 of read text
  and compares against expected hash; compares length against `clipboardTextLength`;
  compares `changeCount` against `clipboardWriteChangeCount` for tamper detection;
  includes long-text (>500 chars) truncated preview in diagnostics.
- Three new SharedKeys: `clipboardTextHash`, `clipboardTextLength`, `clipboardWriteChangeCount`.

**Tests (49 passed, 0 failures in KeyboardTests):**
- Replaced `testChineseSessionFailedRoutesRawFallbackAndFlushesBuffer` (wrong) with
  `testChineseSessionInputErrorDoesNotInsertRawHostText` and `testChineseSessionFailedStatusClearsBufferWithoutInserting` (correct).
- Replaced `testFailedStatusDoesNotReinstallSessionOnEveryKeystroke` (wrong) with the
  retry-backoff behavior.
- Updated `testChineseInputFailureFallsBackToRawHostText` and `testChineseQwertyFlushesBufferedInputAsRawWhenNativeSessionFails`
  to assert host text stays empty.
- Updated `testSecondPasteboardReadCanCaptureLateClipboardText` to match the new
  no-trim read behavior.
- `testExpandedPanelReceivesFullCandidateList` now uses `[CandidateSuggestion]` and
  asserts `chineseCandidateTotalCount`.
- `ThrowingInputChineseRimeBridge` added (starts OK, throws on `input()`).

**Not yet done (deferred follow-up, see section 1.17):**
- Expanded panel left pinyin column + paging/more button UI. The typed data model
  (item 1 above) enables these cleanly; they are UI work on top of the corrected
  data pipeline.
- Physical-device WeChat validation (Phase 9).

**Verification (2026-07-08):**
- `make ios-build-sim` — BUILD SUCCEEDED.
- `make ios-test-sim` — exit 0 (KeyboardTests 49/0 + ChineseInputTests + MashangxieTests + SharedTests).
