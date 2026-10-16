SHELL := /bin/bash
DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData/Lisiere
ARCH ?= $(shell uname -m)

.PHONY: generate build test verify smoke run

generate:
	xcodegen generate

build: generate
	xcodebuild -packageAuthorizationProvider netrc -project Lisiere.xcodeproj -scheme Lisiere -configuration Release \
		-derivedDataPath "$(DERIVED_DATA)" -destination "platform=macOS,arch=$(ARCH)" \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO BROWSER_ENTITLEMENTS=Config/Browser-Local.entitlements build

test: generate
	xcodebuild -packageAuthorizationProvider netrc -project Lisiere.xcodeproj -scheme Lisiere -configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" -destination "platform=macOS,arch=$(ARCH)" \
		-parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
		ENABLE_APP_SANDBOX=NO ENABLE_HARDENED_RUNTIME=NO test

verify: build
	codesign --verify --deep --strict "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app"

smoke: verify
	bash scripts/smoke-launch.sh "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app"

run: build
	open "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app"
