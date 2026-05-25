APP_NAME := MSP430IDE
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR := .build/release
BIN := $(BUILD_DIR)/$(APP_NAME)

.PHONY: all build app run clean debug-build

all: app

build:
	swift build -c release

debug-build:
	swift build

app: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "Built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf .build $(APP_BUNDLE)
