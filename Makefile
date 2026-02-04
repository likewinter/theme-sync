APP_NAME = ThemeSync
BUILD_DIR = build
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
APP_BIN = $(BUILD_DIR)/$(APP_NAME)
MODULE_CACHE = $(BUILD_DIR)/ModuleCache
MIN_TARGET = 13.0
ICON_BASE = $(BUILD_DIR)/AppIconBase.png
ICONSET_DIR = $(BUILD_DIR)/AppIcon.iconset
ICON_ICNS = $(BUILD_DIR)/ThemeSync.icns

SDK_PATH := $(shell xcrun --sdk macosx --show-sdk-path)

.PHONY: app clean icon install

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
		Sources/$(APP_NAME)/main.swift
	@mkdir -p $(APP_DIR)/Contents/MacOS
	@cp $(APP_BIN) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	@mkdir -p $(APP_DIR)/Contents/Resources
	@cp $(ICON_ICNS) $(APP_DIR)/Contents/Resources/ThemeSync.icns
	@cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	@echo "Built $(APP_DIR)"

icon:
	@mkdir -p $(BUILD_DIR) $(ICONSET_DIR)
	@python3 scripts/make_icon.py
	@sips -z 16 16     $(ICON_BASE) --out $(ICONSET_DIR)/icon_16x16.png > /dev/null
	@sips -z 32 32     $(ICON_BASE) --out $(ICONSET_DIR)/icon_16x16@2x.png > /dev/null
	@sips -z 32 32     $(ICON_BASE) --out $(ICONSET_DIR)/icon_32x32.png > /dev/null
	@sips -z 64 64     $(ICON_BASE) --out $(ICONSET_DIR)/icon_32x32@2x.png > /dev/null
	@sips -z 128 128   $(ICON_BASE) --out $(ICONSET_DIR)/icon_128x128.png > /dev/null
	@sips -z 256 256   $(ICON_BASE) --out $(ICONSET_DIR)/icon_128x128@2x.png > /dev/null
	@sips -z 256 256   $(ICON_BASE) --out $(ICONSET_DIR)/icon_256x256.png > /dev/null
	@sips -z 512 512   $(ICON_BASE) --out $(ICONSET_DIR)/icon_256x256@2x.png > /dev/null
	@sips -z 512 512   $(ICON_BASE) --out $(ICONSET_DIR)/icon_512x512.png > /dev/null
	@sips -z 1024 1024 $(ICON_BASE) --out $(ICONSET_DIR)/icon_512x512@2x.png > /dev/null
	@iconutil -c icns $(ICONSET_DIR) -o $(ICON_ICNS)

install: app
	@cp -R $(APP_DIR) /Applications/

clean:
	@rm -rf $(BUILD_DIR)
