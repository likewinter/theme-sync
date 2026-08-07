APP_NAME = ThemeSync
BUILD_DIR = build
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
APP_BIN = $(BUILD_DIR)/$(APP_NAME)
MODULE_CACHE = $(BUILD_DIR)/ModuleCache
MIN_TARGET = 13.0
ICON_BASE = $(BUILD_DIR)/AppIconBase.png
ICONSET_DIR = $(BUILD_DIR)/AppIcon.iconset
ICON_ICNS = $(BUILD_DIR)/ThemeSync.icns

GIT_VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
VERSION ?= $(if $(GIT_VERSION),$(GIT_VERSION),0.0.0)

SDK_PATH := $(shell xcrun --sdk macosx --show-sdk-path)

.PHONY: app clean icon install test release

app: icon
	@mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	@swiftc \
		-sdk $(SDK_PATH) \
		-target arm64-apple-macosx$(MIN_TARGET) \
		-parse-as-library \
		-module-cache-path $(MODULE_CACHE) \
		-framework SwiftUI \
		-framework AppKit \
		-o $(APP_BIN) \
		Sources/$(APP_NAME)/ScriptRunner.swift \
		Sources/$(APP_NAME)/main.swift
	@mkdir -p $(APP_DIR)/Contents/MacOS
	@cp $(APP_BIN) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	@mkdir -p $(APP_DIR)/Contents/Resources
	@cp $(ICON_ICNS) $(APP_DIR)/Contents/Resources/ThemeSync.icns
	@cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_DIR)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_DIR)/Contents/Info.plist
	@echo "Built $(APP_DIR) (version $(VERSION))"

icon:
	@mkdir -p $(BUILD_DIR) $(ICONSET_DIR)
	@python3 scripts/make_icon.py

install: app
	@cp -R $(APP_DIR) /Applications/

test:
	@mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	@swiftc \
		-sdk $(SDK_PATH) \
		-target arm64-apple-macosx$(MIN_TARGET) \
		-module-cache-path $(MODULE_CACHE) \
		-o $(BUILD_DIR)/ThemeSyncTests \
		Sources/$(APP_NAME)/ScriptRunner.swift \
		Tests/ThemeSyncTests/ScriptRunnerTests.swift
	@$(BUILD_DIR)/ThemeSyncTests

clean:
	@rm -rf $(BUILD_DIR)

release:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make release VERSION=1.1.0"; exit 1; fi
	@git tag v$(VERSION)
	@git push origin v$(VERSION)
