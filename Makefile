APP_NAME := VoxFlow
SWIFT_EXECUTABLE := VoxFlowApp
BUILD_DIR := .build
SWIFTPM_BUILD_DIR := $(BUILD_DIR)/swiftpm-xcode16
BUNDLE_DIR := $(BUILD_DIR)/release/$(APP_NAME).app
DEV_BUNDLE_DIR := $(BUILD_DIR)/dev/$(APP_NAME).app
RESOURCE_BUNDLE_NAME := $(SWIFT_EXECUTABLE)_$(SWIFT_EXECUTABLE).bundle
SCREENSHOT_RESOURCE_BUNDLE_NAME := $(SWIFT_EXECUTABLE)_VoxFlowScreenshotKit.bundle
COPY_RESOURCE_BUNDLES = for bundle in "$(1)"/*.bundle; do \
		[ -d "$$bundle" ] || continue; \
		case "$$(basename "$$bundle")" in *Tests.bundle) continue ;; esac; \
		cp -R "$$bundle" "$(2)/Contents/Resources/"; \
	done
VOXFLOW_DEVELOPER_DIR ?= $(HOME)/Applications/Xcode-16.4.0.app/Contents/Developer
ifneq ($(wildcard $(VOXFLOW_DEVELOPER_DIR)),)
export DEVELOPER_DIR := $(VOXFLOW_DEVELOPER_DIR)
endif
SWIFT := xcrun swift
SWIFT_PACKAGE_FLAGS := --scratch-path $(SWIFTPM_BUILD_DIR)
ARM_RELEASE_BIN_DIR := $(SWIFTPM_BUILD_DIR)/arm64-apple-macosx/release
SWIFT_NATIVE_ARCH := $(shell uname -m)
NATIVE_RELEASE_BIN_DIR := $(SWIFTPM_BUILD_DIR)/$(SWIFT_NATIVE_ARCH)-apple-macosx/release
NATIVE_DEBUG_BIN_DIR := $(SWIFTPM_BUILD_DIR)/$(SWIFT_NATIVE_ARCH)-apple-macosx/debug
INSTALL_DIR := /Applications/$(APP_NAME).app
PLIST := Sources/VoxFlowApp/Resources/Info.plist
LOCALE_LPROJ_DIRS := Sources/VoxFlowApp/Resources/en.lproj Sources/VoxFlowApp/Resources/zh-Hans.lproj Sources/VoxFlowApp/Resources/zh-Hant.lproj Sources/VoxFlowApp/Resources/ja.lproj Sources/VoxFlowApp/Resources/ko.lproj
ICON := Resources/AppIcon.icns
SHERPA_ONNX_LIB := Vendor/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx.a
ONNXRUNTIME_LIB := Vendor/sherpa-onnx.xcframework/macos-arm64_x86_64/libonnxruntime.a
MLX_METALLIB_SCRIPT := scripts/build-mlx-metallib.sh
VERIFY_RUNTIME_BUNDLES_SCRIPT := scripts/verify-runtime-bundles.sh
MLX_METALLIB := mlx.metallib
MLX_DEFAULT_METALLIB := default.metallib
RUST_CARGO ?= $(shell rustup which cargo 2>/dev/null || command -v cargo 2>/dev/null)
RUSTC ?= $(shell rustup which rustc 2>/dev/null || command -v rustc 2>/dev/null)
AGENT_HELPER_MANIFEST := agent-cli/Cargo.toml
AGENT_HELPER_BINARY := agent-cli/target/release/voxflow
CURRENT_BUNDLE_ID := com.voxflow.app
DEV_BUNDLE_ID := com.voxflow.app.dev
DEV_BUNDLE_NAME := VoxFlow Dev
DEV_DISPLAY_NAME := 码上写 Dev
STATUS_ITEM_AUTOSAVE_NAMES := VoxFlowMenuBarItem
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DETECTED_DEVELOPMENT_CODE_SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/Apple Development/ { print $$2; exit }')
DEVELOPMENT_CODE_SIGN_IDENTITY ?= $(if $(DETECTED_DEVELOPMENT_CODE_SIGN_IDENTITY),$(DETECTED_DEVELOPMENT_CODE_SIGN_IDENTITY),-)
RELEASE_CODE_SIGN_IDENTITY ?= VoxFlow Release Signing
RELEASE_KEYCHAIN_PATH ?=
CODE_SIGN_IDENTITY ?= $(DEVELOPMENT_CODE_SIGN_IDENTITY)
CODE_SIGN_KEYCHAIN_OPTION := $(if $(RELEASE_KEYCHAIN_PATH),--keychain "$(RELEASE_KEYCHAIN_PATH)",)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$(PLIST)")
DMG_NAME := VoxFlow-$(VERSION)-macOS
DMG_FILE := dist/$(DMG_NAME).dmg
UPDATE_DEBUG_ENV_KEYS := VOXFLOW_UPDATE_CHECK_MOCK VOXFLOW_UPDATE_CHECK_FIXTURE
LOCAL_ENV_FILE ?= .env.local
SENTRY_CLI_VERSION ?= 2.52.0
SENTRY_CLI := $(CURDIR)/.build/tools/sentry-cli

ifneq ($(wildcard $(LOCAL_ENV_FILE)),)
include $(LOCAL_ENV_FILE)
endif

export VOXFLOW_SENTRY_DSN
export SENTRY_AUTH_TOKEN
export SENTRY_ORG
export SENTRY_PROJECT

SWIFT_RELEASE_FLAGS := -c release -Xswiftc -Osize
SWIFT_DEBUG_FLAGS := -c debug -Xswiftc -warnings-as-errors

.PHONY: all prepare-release prepare-runtime prepare-agent-helper require-release-signing-identity test architecture-check smoke-asr-provider smoke-asr-live build build-native build-dev run run-native run-dev sentry-upload-dev-dsym install dmg release release-check apply-launch-env clean debug prelaunch-cleanup gen-l10n lint i18n-check

all: build

prepare-runtime: $(SHERPA_ONNX_LIB) $(ONNXRUNTIME_LIB)

prepare-agent-helper:
	@command -v "$(RUST_CARGO)" >/dev/null 2>&1 || (echo "Rust cargo not found. Install Rust or set RUST_CARGO=/path/to/cargo" && exit 1)
	@command -v "$(RUSTC)" >/dev/null 2>&1 || (echo "Rust compiler not found. Install Rust or set RUSTC=/path/to/rustc" && exit 1)
	RUSTC="$(RUSTC)" "$(RUST_CARGO)" build --release --manifest-path "$(AGENT_HELPER_MANIFEST)"
	@test -x "$(AGENT_HELPER_BINARY)"

$(SHERPA_ONNX_LIB) $(ONNXRUNTIME_LIB):
	@./scripts/bootstrap-sherpa-onnx.sh

test: prepare-runtime
	$(SWIFT) test $(SWIFT_PACKAGE_FLAGS)

architecture-check:
	python3 scripts/architecture_check.py --package Package.swift --source-root Sources

smoke-asr-provider:
	$(SWIFT) test $(SWIFT_PACKAGE_FLAGS) --filter VoxFlowProviderSmokeTests

smoke-asr-live:
	@test -n "$(PROVIDER)" || (echo "Set PROVIDER=qwen3|whisper|funasr|sensevoice" && exit 2)
	VOICEINPUT_TEST_ASR_SMOKE_PROVIDER=$(PROVIDER) $(SWIFT) test $(SWIFT_PACKAGE_FLAGS) --filter ASRProviderLiveSmokeTests

build: prepare-runtime prepare-agent-helper
	@echo "🔨 Building $(APP_NAME)..."
	$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_RELEASE_FLAGS) --arch arm64
	@BUILD_DIR="$(CURDIR)/$(SWIFTPM_BUILD_DIR)" bash "$(MLX_METALLIB_SCRIPT)" release
	@echo "📦 Creating app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Helpers"
	@cp "$(ARM_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)" "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"
	@cp "$(ARM_RELEASE_BIN_DIR)/$(MLX_METALLIB)" "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@cp "$(ARM_RELEASE_BIN_DIR)/$(MLX_DEFAULT_METALLIB)" "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@cp "$(AGENT_HELPER_BINARY)" "$(BUNDLE_DIR)/Contents/Helpers/voxflow"
	@ln -s voxflow "$(BUNDLE_DIR)/Contents/Helpers/vox"
	@chmod 755 "$(BUNDLE_DIR)/Contents/Helpers/voxflow" "$(BUNDLE_DIR)/Contents/Helpers/vox"
	@test -d "$(ARM_RELEASE_BIN_DIR)/$(RESOURCE_BUNDLE_NAME)"
	@test -d "$(ARM_RELEASE_BIN_DIR)/$(SCREENSHOT_RESOURCE_BUNDLE_NAME)"
	@$(call COPY_RESOURCE_BUNDLES,$(ARM_RELEASE_BIN_DIR),$(BUNDLE_DIR))
	@for dir in $(LOCALE_LPROJ_DIRS); do cp -R "$$dir" "$(BUNDLE_DIR)/Contents/Resources/"; done
	@lipo "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" -verify_arch arm64
	@test -f "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@test -f "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@cp "$(PLIST)" "$(BUNDLE_DIR)/Contents/"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)" "$(BUNDLE_DIR)/Contents/Info.plist"
	@if [ -n "$${VOXFLOW_SENTRY_DSN:-}" ]; then /usr/libexec/PlistBuddy -c "Set :VoxFlowSentryDSN $${VOXFLOW_SENTRY_DSN}" "$(BUNDLE_DIR)/Contents/Info.plist"; fi
	@/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$(BUNDLE_DIR)/Contents/Info.plist" >/dev/null
	@/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$(BUNDLE_DIR)/Contents/Info.plist" >/dev/null
	@cp "$(ICON)" "$(BUNDLE_DIR)/Contents/Resources/"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/AppDatabaseSchema.sql"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/AuthorWeChatQRCode.jpg"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/GitHubMark.png"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(SCREENSHOT_RESOURCE_BUNDLE_NAME)/en.lproj/ScreenshotKit.strings"
	@bash "$(VERIFY_RUNTIME_BUNDLES_SCRIPT)" "$(ARM_RELEASE_BIN_DIR)" "$(BUNDLE_DIR)"
	@plutil -lint "$(BUNDLE_DIR)/Contents/Info.plist"
	@echo "🔏 Signing with: $(CODE_SIGN_IDENTITY)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/Helpers/voxflow"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/Helpers/vox"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)"
	@codesign --verify --deep --strict "$(BUNDLE_DIR)"
	@"$(LSREGISTER)" -f "$(BUNDLE_DIR)" >/dev/null 2>&1 || true
	@echo "✅ Build complete: $(BUNDLE_DIR)"

build-native: prepare-runtime prepare-agent-helper
	@echo "🔨 Building $(APP_NAME) for native $(SWIFT_NATIVE_ARCH)..."
	$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_RELEASE_FLAGS) --arch $(SWIFT_NATIVE_ARCH)
	@BUILD_DIR="$(CURDIR)/$(SWIFTPM_BUILD_DIR)" bash "$(MLX_METALLIB_SCRIPT)" release
	@echo "📦 Creating native app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Helpers"
	@cp "$(NATIVE_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)" "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"
	@cp "$(NATIVE_RELEASE_BIN_DIR)/$(MLX_METALLIB)" "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@cp "$(NATIVE_RELEASE_BIN_DIR)/$(MLX_DEFAULT_METALLIB)" "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@cp "$(AGENT_HELPER_BINARY)" "$(BUNDLE_DIR)/Contents/Helpers/voxflow"
	@ln -s voxflow "$(BUNDLE_DIR)/Contents/Helpers/vox"
	@chmod 755 "$(BUNDLE_DIR)/Contents/Helpers/voxflow" "$(BUNDLE_DIR)/Contents/Helpers/vox"
	@test -d "$(NATIVE_RELEASE_BIN_DIR)/$(RESOURCE_BUNDLE_NAME)"
	@test -d "$(NATIVE_RELEASE_BIN_DIR)/$(SCREENSHOT_RESOURCE_BUNDLE_NAME)"
	@$(call COPY_RESOURCE_BUNDLES,$(NATIVE_RELEASE_BIN_DIR),$(BUNDLE_DIR))
	@for dir in $(LOCALE_LPROJ_DIRS); do cp -R "$$dir" "$(BUNDLE_DIR)/Contents/Resources/"; done
	@lipo "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" -verify_arch $(SWIFT_NATIVE_ARCH)
	@test -f "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@test -f "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@cp "$(PLIST)" "$(BUNDLE_DIR)/Contents/"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)" "$(BUNDLE_DIR)/Contents/Info.plist"
	@if [ -n "$${VOXFLOW_SENTRY_DSN:-}" ]; then /usr/libexec/PlistBuddy -c "Set :VoxFlowSentryDSN $${VOXFLOW_SENTRY_DSN}" "$(BUNDLE_DIR)/Contents/Info.plist"; fi
	@/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$(BUNDLE_DIR)/Contents/Info.plist" >/dev/null
	@/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$(BUNDLE_DIR)/Contents/Info.plist" >/dev/null
	@cp "$(ICON)" "$(BUNDLE_DIR)/Contents/Resources/"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/AppDatabaseSchema.sql"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/AuthorWeChatQRCode.jpg"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/GitHubMark.png"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(SCREENSHOT_RESOURCE_BUNDLE_NAME)/en.lproj/ScreenshotKit.strings"
	@bash "$(VERIFY_RUNTIME_BUNDLES_SCRIPT)" "$(NATIVE_RELEASE_BIN_DIR)" "$(BUNDLE_DIR)"
	@plutil -lint "$(BUNDLE_DIR)/Contents/Info.plist"
	@echo "🔏 Signing with: $(CODE_SIGN_IDENTITY)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/Helpers/voxflow"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)/Contents/Helpers/vox"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(BUNDLE_DIR)"
	@codesign --verify --deep --strict "$(BUNDLE_DIR)"
	@"$(LSREGISTER)" -f "$(BUNDLE_DIR)" >/dev/null 2>&1 || true
	@echo "✅ Native build complete: $(BUNDLE_DIR)"

build-dev: prepare-runtime prepare-agent-helper
	@echo "🔨 Building debug $(APP_NAME) for native $(SWIFT_NATIVE_ARCH)..."
	$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_DEBUG_FLAGS) --arch $(SWIFT_NATIVE_ARCH)
	@BUILD_DIR="$(CURDIR)/$(SWIFTPM_BUILD_DIR)" bash "$(MLX_METALLIB_SCRIPT)" debug
	@echo "📦 Creating debug app bundle..."
	@rm -rf "$(DEV_BUNDLE_DIR)"
	@mkdir -p "$(DEV_BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(DEV_BUNDLE_DIR)/Contents/Resources"
	@mkdir -p "$(DEV_BUNDLE_DIR)/Contents/Helpers"
	@cp "$(NATIVE_DEBUG_BIN_DIR)/$(SWIFT_EXECUTABLE)" "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"
	@cp "$(NATIVE_DEBUG_BIN_DIR)/$(MLX_METALLIB)" "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@cp "$(NATIVE_DEBUG_BIN_DIR)/$(MLX_DEFAULT_METALLIB)" "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@cp "$(AGENT_HELPER_BINARY)" "$(DEV_BUNDLE_DIR)/Contents/Helpers/voxflow"
	@ln -s voxflow "$(DEV_BUNDLE_DIR)/Contents/Helpers/vox"
	@chmod 755 "$(DEV_BUNDLE_DIR)/Contents/Helpers/voxflow" "$(DEV_BUNDLE_DIR)/Contents/Helpers/vox"
	@test -d "$(NATIVE_DEBUG_BIN_DIR)/$(RESOURCE_BUNDLE_NAME)"
	@test -d "$(NATIVE_DEBUG_BIN_DIR)/$(SCREENSHOT_RESOURCE_BUNDLE_NAME)"
	@$(call COPY_RESOURCE_BUNDLES,$(NATIVE_DEBUG_BIN_DIR),$(DEV_BUNDLE_DIR))
	@for dir in $(LOCALE_LPROJ_DIRS); do cp -R "$$dir" "$(DEV_BUNDLE_DIR)/Contents/Resources/"; done
	@lipo "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" -verify_arch $(SWIFT_NATIVE_ARCH)
	@test -f "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@test -f "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@cp "$(PLIST)" "$(DEV_BUNDLE_DIR)/Contents/"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(DEV_BUNDLE_ID)" "$(DEV_BUNDLE_DIR)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleName $(DEV_BUNDLE_NAME)" "$(DEV_BUNDLE_DIR)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $(DEV_DISPLAY_NAME)" "$(DEV_BUNDLE_DIR)/Contents/Info.plist"
	@if [ -n "$${VOXFLOW_SENTRY_DSN:-}" ]; then /usr/libexec/PlistBuddy -c "Set :VoxFlowSentryDSN $${VOXFLOW_SENTRY_DSN}" "$(DEV_BUNDLE_DIR)/Contents/Info.plist"; fi
	@/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$(DEV_BUNDLE_DIR)/Contents/Info.plist" >/dev/null
	@/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$(DEV_BUNDLE_DIR)/Contents/Info.plist" >/dev/null
	@cp "$(ICON)" "$(DEV_BUNDLE_DIR)/Contents/Resources/"
	@test -f "$(DEV_BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/AppDatabaseSchema.sql"
	@test -f "$(DEV_BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/AuthorWeChatQRCode.jpg"
	@test -f "$(DEV_BUNDLE_DIR)/Contents/Resources/$(RESOURCE_BUNDLE_NAME)/GitHubMark.png"
	@test -f "$(DEV_BUNDLE_DIR)/Contents/Resources/$(SCREENSHOT_RESOURCE_BUNDLE_NAME)/en.lproj/ScreenshotKit.strings"
	@bash "$(VERIFY_RUNTIME_BUNDLES_SCRIPT)" "$(NATIVE_DEBUG_BIN_DIR)" "$(DEV_BUNDLE_DIR)"
	@plutil -lint "$(DEV_BUNDLE_DIR)/Contents/Info.plist"
	@echo "🔏 Signing with: $(CODE_SIGN_IDENTITY)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(DEV_BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(DEV_BUNDLE_DIR)/Contents/Helpers/voxflow"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(DEV_BUNDLE_DIR)/Contents/Helpers/vox"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" $(CODE_SIGN_KEYCHAIN_OPTION) "$(DEV_BUNDLE_DIR)"
	@codesign --verify --deep --strict "$(DEV_BUNDLE_DIR)"
	@"$(LSREGISTER)" -f "$(DEV_BUNDLE_DIR)" >/dev/null 2>&1 || true
	@echo "✅ Debug app build complete: $(DEV_BUNDLE_DIR)"

run: prelaunch-cleanup build apply-launch-env
	@echo "🚀 Launching $(APP_NAME)..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	open "$(BUNDLE_DIR)"

run-native: prelaunch-cleanup build-native apply-launch-env
	@echo "🚀 Launching native $(APP_NAME)..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	open "$(BUNDLE_DIR)"

run-dev: prelaunch-cleanup build-dev apply-launch-env
	@echo "🚀 Launching debug native $(APP_NAME)..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	open -n "$(CURDIR)/$(DEV_BUNDLE_DIR)"
	@for attempt in 1 2 3 4 5 6 7 8 9 10; do \
		if ps -axo command= | grep -F "$(CURDIR)/$(DEV_BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" | grep -v grep >/dev/null; then \
			exit 0; \
		fi; \
		sleep 0.2; \
	done; \
	echo "❌ Expected dev app to launch from $(CURDIR)/$(DEV_BUNDLE_DIR), but running $(APP_NAME) processes are:"; \
	ps -axo pid,command | grep -F "/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" | grep -v grep || true; \
	exit 1

$(SENTRY_CLI):
	@mkdir -p "$(dir $(SENTRY_CLI))"
	curl -sL "https://downloads.sentry-cdn.com/sentry-cli/$(SENTRY_CLI_VERSION)/sentry-cli-Darwin-universal" -o "$(SENTRY_CLI)"
	chmod +x "$(SENTRY_CLI)"
	"$(SENTRY_CLI)" --version

sentry-upload-dev-dsym: build-dev $(SENTRY_CLI)
	PATH="$(dir $(SENTRY_CLI)):$$PATH" scripts/upload-sentry-dsym.sh "$(DEV_BUNDLE_DIR)" "$(DEV_BUNDLE_DIR).dSYM"

apply-launch-env:
	@for key in $(UPDATE_DEBUG_ENV_KEYS); do \
		value=$$(printenv $$key); \
		if [ -n "$$value" ]; then \
			launchctl setenv "$$key" "$$value"; \
		else \
			launchctl unsetenv "$$key" 2>/dev/null || true; \
		fi; \
	done

prelaunch-cleanup:
	@echo "🧽 Cleaning stale local app registration..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -x "$(SWIFT_EXECUTABLE)" 2>/dev/null || true
	@pkill -f "$(CURDIR)/$(BUNDLE_DIR)/Contents/Helpers/[v]oxflow serve" 2>/dev/null || true
	@pkill -f "$(CURDIR)/$(DEV_BUNDLE_DIR)/Contents/Helpers/[v]oxflow serve" 2>/dev/null || true
	@for app in \
		"$(BUNDLE_DIR)" \
		"$(DEV_BUNDLE_DIR)" \
		".build/$(APP_NAME).app" \
		".build/$(SWIFT_EXECUTABLE).app" \
		"dist/staging/$(APP_NAME).app" \
		"/Applications/$(APP_NAME).app" \
		"/Applications/$(SWIFT_EXECUTABLE).app" \
		/private/tmp/voxflow-dmg-smoke.*/$(APP_NAME).app; do \
		"$(LSREGISTER)" -u "$$app" >/dev/null 2>&1 || true; \
	done
	@rm -rf ".build/$(APP_NAME).app"
	@for bundle_id in "$(CURRENT_BUNDLE_ID)" "$(DEV_BUNDLE_ID)"; do \
		for autosave_name in $(STATUS_ITEM_AUTOSAVE_NAMES); do \
			defaults delete "$$bundle_id" "NSStatusItem Preferred Position $$autosave_name" 2>/dev/null || true; \
			defaults delete "$$bundle_id" "NSStatusItem Visible $$autosave_name" 2>/dev/null || true; \
			defaults delete "$$bundle_id" "NSStatusItem VisibleCC $$autosave_name" 2>/dev/null || true; \
		done; \
		defaults delete "$$bundle_id" "VoxFlowStatusItemPlacementResetV1" 2>/dev/null || true; \
	done
	@killall cfprefsd 2>/dev/null || true
	@killall ControlCenter 2>/dev/null || true

install: build
	@echo "📥 Installing to $(INSTALL_DIR)..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	@rm -rf "$(INSTALL_DIR)"
	@ditto "$(BUNDLE_DIR)" "$(INSTALL_DIR)"
	@codesign --verify --deep --strict "$(INSTALL_DIR)"
	@echo "✅ Installed: $(INSTALL_DIR)"

require-release-signing-identity:
	@test -n "$(RELEASE_CODE_SIGN_IDENTITY)" || (echo "RELEASE_CODE_SIGN_IDENTITY is required for release packaging" && exit 2)
	@test "$(RELEASE_CODE_SIGN_IDENTITY)" != "-" || (echo "Ad-hoc signing is not allowed for release packaging" && exit 2)
	@if [ -n "$(RELEASE_KEYCHAIN_PATH)" ]; then \
		test -f "$(RELEASE_KEYCHAIN_PATH)" || (echo "Release signing keychain not found: $(RELEASE_KEYCHAIN_PATH)" && exit 2); \
	else \
		security find-identity -v -p codesigning 2>/dev/null | grep -F -- "$(RELEASE_CODE_SIGN_IDENTITY)" >/dev/null || (echo "Release signing identity not found: $(RELEASE_CODE_SIGN_IDENTITY)" && exit 2); \
	fi

dmg: CODE_SIGN_IDENTITY = $(RELEASE_CODE_SIGN_IDENTITY)
dmg: require-release-signing-identity build
	@echo "💿 Creating DMG installer..."
	@mkdir -p dist
	@rm -rf dist/staging
	@mkdir -p dist/staging
	@cp -R "$(BUNDLE_DIR)" dist/staging/
	@ln -s /Applications dist/staging/
	@rm -f "$(DMG_FILE)"
	@dmg_size_mb=$$(du -sm dist/staging | awk '{ print $$1 + 256 }'); \
	for attempt in 1 2 3; do \
		if hdiutil create -volname "$(DMG_NAME)" \
			-srcfolder dist/staging \
			-size $${dmg_size_mb}m \
			-ov -format UDZO \
			-imagekey zlib-level=9 \
			"$(DMG_FILE)" > /dev/null; then \
			break; \
		fi; \
		if [ "$$attempt" = "3" ]; then \
			exit 1; \
		fi; \
		echo "hdiutil create failed, retrying ($$attempt/3)..."; \
		hdiutil detach "/Volumes/$(DMG_NAME)" -force >/dev/null 2>&1 || true; \
		rm -f "$(DMG_FILE)"; \
		sleep 5; \
	done
	@rm -rf dist/staging
	@shasum -a 256 "$(DMG_FILE)" > "$(DMG_FILE).sha256"
	@echo "✅ DMG created: $(DMG_FILE)"

release: dmg
	@echo "📦 Release package: $(DMG_FILE)"
	@echo "📄 Checksum:   $(DMG_FILE).sha256"

release-check:
	python3 scripts/check-release-metadata.py

gen-l10n:
	@command -v swiftgen >/dev/null 2>&1 || (echo "swiftgen not found. Run: brew install swiftgen" && exit 1)
	@mkdir -p Sources/VoxFlowApp/Generated
	swiftgen config run --config swiftgen.yml

lint:
	@command -v swiftlint >/dev/null 2>&1 || (echo "swiftlint not found. Run: brew install swiftlint" && exit 1)
	swiftlint lint --strict Sources/

i18n-check:
	@command -v bartycrouch >/dev/null 2>&1 || (echo "bartycrouch not found. Run: brew install bartycrouch" && exit 1)
	bartycrouch lint --path Sources/VoxFlowApp/Resources
	bartycrouch lint --path Sources/VoxFlowScreenshotKit/Resources
	python3 scripts/check-localization.py

prepare-release:
	@test "$(origin VERSION)" = "command line" || (echo "Set VERSION=x.y.z" && exit 2)
	@test -n "$(BUILD)" || (echo "Set BUILD=n" && exit 2)
	python3 scripts/prepare-release.py --version "$(VERSION)" --build "$(BUILD)"
	$(MAKE) release-check

clean:
	@echo "🧹 Cleaning..."
	@rm -rf "$(BUNDLE_DIR)" "$(DEV_BUNDLE_DIR)" "$(SWIFTPM_BUILD_DIR)" ".build/$(APP_NAME).app" dist/staging
	@echo "✅ Clean complete"

debug: prepare-runtime
	$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) -c debug -Xswiftc -warnings-as-errors
