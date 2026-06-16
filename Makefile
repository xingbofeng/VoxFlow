APP_NAME := VoxFlow
SWIFT_EXECUTABLE := VoiceInputApp
BUILD_DIR := .build
BUNDLE_DIR := $(BUILD_DIR)/$(APP_NAME).app
ARM_RELEASE_BIN_DIR := $(BUILD_DIR)/arm64-apple-macosx/release
X86_RELEASE_BIN_DIR := $(BUILD_DIR)/x86_64-apple-macosx/release
INSTALL_DIR := /Applications/$(APP_NAME).app
PLIST := Sources/VoiceInputApp/Resources/Info.plist
ICON := Resources/AppIcon.icns
CURRENT_BUNDLE_ID := com.xingbofeng.VoxFlow
LEGACY_BUNDLE_ID := com.voiceinput.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DETECTED_CODE_SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/Developer ID Application|Apple Development/ { print $$2; exit }')
CODE_SIGN_IDENTITY ?= $(if $(DETECTED_CODE_SIGN_IDENTITY),$(DETECTED_CODE_SIGN_IDENTITY),-)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$(PLIST)")
DMG_NAME := VoxFlow-$(VERSION)-macOS
DMG_FILE := dist/$(DMG_NAME).dmg

SWIFT_RELEASE_FLAGS := -c release -Xswiftc -Osize

.PHONY: all prepare-runtime test build run install dmg release clean debug prelaunch-cleanup

all: build

prepare-runtime:
	@./scripts/bootstrap-sherpa-onnx.sh

test: prepare-runtime
	swift test

build: prepare-runtime
	@echo "🔨 Building $(APP_NAME)..."
	swift build $(SWIFT_RELEASE_FLAGS) --arch arm64
	swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64
	@echo "📦 Creating app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@lipo -create \
		"$(ARM_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)" \
		"$(X86_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)" \
		-output "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"
	@if [ -d "$(ARM_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)_$(SWIFT_EXECUTABLE).bundle" ]; then \
		cp -R "$(ARM_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)_$(SWIFT_EXECUTABLE).bundle" "$(BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@lipo "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" -verify_arch arm64 x86_64
	@cp "$(PLIST)" "$(BUNDLE_DIR)/Contents/"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)" "$(BUNDLE_DIR)/Contents/Info.plist"
	@cp "$(ICON)" "$(BUNDLE_DIR)/Contents/Resources/"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(SWIFT_EXECUTABLE)_$(SWIFT_EXECUTABLE).bundle/AuthorWeChatQRCode.jpg"
	@test -f "$(BUNDLE_DIR)/Contents/Resources/$(SWIFT_EXECUTABLE)_$(SWIFT_EXECUTABLE).bundle/GitHubMark.png"
	@plutil -lint "$(BUNDLE_DIR)/Contents/Info.plist"
	@echo "🔏 Signing with: $(CODE_SIGN_IDENTITY)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(BUNDLE_DIR)"
	@codesign --verify --deep --strict "$(BUNDLE_DIR)"
	@echo "✅ Build complete: $(BUNDLE_DIR)"

run: prelaunch-cleanup build
	@echo "🚀 Launching $(APP_NAME)..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	open "$(BUNDLE_DIR)"

prelaunch-cleanup:
	@echo "🧽 Cleaning stale local app registration and legacy status bar cache..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -x "$(SWIFT_EXECUTABLE)" 2>/dev/null || true
	@for app in \
		"$(BUNDLE_DIR)" \
		".build/$(SWIFT_EXECUTABLE).app" \
		"dist/staging/$(APP_NAME).app" \
		"/Applications/$(SWIFT_EXECUTABLE).app"; do \
		"$(LSREGISTER)" -u "$$app" >/dev/null 2>&1 || true; \
	done
	@defaults delete "$(LEGACY_BUNDLE_ID)" "NSStatusItem Preferred Position VoxFlowStatusItem" 2>/dev/null || true
	@defaults delete "$(LEGACY_BUNDLE_ID)" "NSStatusItem Preferred Position VoxFlowStatusItemV2" 2>/dev/null || true
	@defaults delete "$(LEGACY_BUNDLE_ID)" "NSStatusItem VisibleCC VoxFlowStatusItem" 2>/dev/null || true
	@defaults delete "$(LEGACY_BUNDLE_ID)" "NSStatusItem VisibleCC VoxFlowStatusItemV2" 2>/dev/null || true

install: build
	@echo "📥 Installing to $(INSTALL_DIR)..."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	@rm -rf "$(INSTALL_DIR)"
	@ditto "$(BUNDLE_DIR)" "$(INSTALL_DIR)"
	@codesign --verify --deep --strict "$(INSTALL_DIR)"
	@echo "✅ Installed: $(INSTALL_DIR)"

dmg: build
	@echo "💿 Creating DMG installer..."
	@mkdir -p dist
	@rm -rf dist/staging
	@mkdir -p dist/staging
	@cp -R "$(BUNDLE_DIR)" dist/staging/
	@ln -s /Applications dist/staging/
	@rm -f "$(DMG_FILE)"
	@hdiutil create -volname "$(DMG_NAME)" \
		-srcfolder dist/staging \
		-ov -format UDZO \
		-imagekey zlib-level=9 \
		"$(DMG_FILE)" > /dev/null
	@rm -rf dist/staging
	@shasum -a 256 "$(DMG_FILE)" > "$(DMG_FILE).sha256"
	@echo "✅ DMG created: $(DMG_FILE)"

release: dmg
	@echo "📦 Release package: $(DMG_FILE)"
	@echo "📄 Checksum:   $(DMG_FILE).sha256"

clean:
	@echo "🧹 Cleaning..."
	@rm -rf "$(BUNDLE_DIR)" dist/staging
	swift package clean
	@echo "✅ Clean complete"

debug: prepare-runtime
	swift build -c debug -Xswiftc -warnings-as-errors
