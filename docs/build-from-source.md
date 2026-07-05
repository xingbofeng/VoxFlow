# Build From Source

VoxFlow is a native macOS app built with Swift 6, SwiftUI/AppKit, SwiftPM, local ASR runtimes, and a Rust helper for AI Coding Assistant workflows.

## Requirements

- macOS 15 or later
- Xcode 16.4 or compatible Swift 6 toolchain
- Rust toolchain for `agent-cli/`
- A microphone for runtime testing

## Common Commands

Use the Makefile entry points instead of `swift run`; packaged app behavior depends on signing, resources, helper binaries, LaunchServices registration, and runtime assets.

```bash
make run-dev      # Daily development: Debug, native arch, package and launch .app
make build-dev    # Debug native build and package, without launching
make run-native   # Native Release launch
make build-native # Native Release build
make build        # Release app build
make debug        # Debug build with warnings as errors
make test         # Run tests
make install      # Install into /Applications
make dmg          # Build DMG
```

Development cleanup is split:

```bash
make run-dev          # Stops VoxFlow processes only before launching
make clean-ls-cache   # Explicit LaunchServices/status item cache cleanup
make reset-dev-state  # Process cleanup + LaunchServices/status item cache cleanup
```

## Source Layout

```text
Sources/VoxFlowApp/             # App shell, UI, lifecycle glue, composition root
Sources/VoxFlowDomain/          # Domain models and task state
Sources/VoxFlowAudio/           # Audio capture and frame handling
Sources/VoxFlowASRCore/         # ASR provider/session/event protocols
Sources/VoxFlowProviders/       # Provider runtime targets
Sources/VoxFlowModelStore/      # Model manifests, install state, repair/prewarm
Sources/VoxFlowTextInsertion/   # Clipboard transaction and text insertion
Sources/VoxFlowScreenshotKit/   # Screenshot capture, annotation, OCR windows
Packages/VoxFlowVoiceCorrectionKit/ # Personal Corrections engine and fixtures
agent-cli/                      # Rust helper/router for AI Coding Assistant
Tests/                          # Swift tests
Resources/                      # App icon and resources
Vendor/                         # Local runtime/vendor assets
docs/                           # Documentation and GitHub Pages site
scripts/                        # Build, benchmark, architecture checks
```

## Verification

For broad local validation:

```bash
swift test
make debug
make build
make i18n-check
make architecture-check
```

Small fixes can use focused tests and a targeted build, but changes touching storage, credentials, output, ASR selection, localization, or app startup should include focused tests and at least `make debug`.

## Notes

- App product: `VoxFlow.app`
- Bundle ID: `com.voxflow.app`
- Dev bundle ID: `com.voxflow.app.dev`
- User data: `~/Library/Application Support/VoxFlow/`
- Primary database: `voxflow.sqlite`
- Credential service: `com.voxflow.app.credentials`
