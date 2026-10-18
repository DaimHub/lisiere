SHELL := /bin/bash
DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData/Lisiere
TEST_CONFIGURATION ?= Debug
TEST_ARGUMENTS ?=
RESULT_BUNDLE ?= $(DERIVED_DATA)/TestResults/$(TEST_CONFIGURATION)-$(shell date +%Y%m%d-%H%M%S).xcresult
QA_OUTPUT ?= $(DERIVED_DATA)/Validation/$(shell date +%Y%m%d-%H%M%S)
ARCH ?= $(shell uname -m)

.PHONY: generate build test tooling-test verify smoke run validate

generate:
	python3 scripts/check-toolchain.py
	xcodegen generate

build: generate
	xcodebuild -packageAuthorizationProvider netrc -project Lisiere.xcodeproj -scheme Lisiere -configuration Release \
		-derivedDataPath "$(DERIVED_DATA)" -destination "platform=macOS,arch=$(ARCH)" \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO BROWSER_ENTITLEMENTS=Config/Browser-Local.entitlements build

test: generate
	@mkdir -p "$(dir $(RESULT_BUNDLE))"
	xcodebuild -packageAuthorizationProvider netrc -project Lisiere.xcodeproj -scheme Lisiere -configuration "$(TEST_CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" -destination "platform=macOS,arch=$(ARCH)" \
		-parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
		ENABLE_APP_SANDBOX=NO ENABLE_HARDENED_RUNTIME=NO ENABLE_TESTABILITY=YES \
		BROWSER_BUNDLE_IDENTIFIER=io.github.daimhub.lisiere.testhost \
		-resultBundlePath "$(RESULT_BUNDLE)" $(TEST_ARGUMENTS) test
	python3 scripts/check-test-results.py "$(RESULT_BUNDLE)"

verify: build
	codesign --verify --deep --strict "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app"

smoke: verify
	python3 scripts/validate-release.py "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app" --output "$(QA_OUTPUT)/standard"
	python3 scripts/validate-release.py "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app" --output "$(QA_OUTPUT)/reduced" --reduce-motion

tooling-test:
	python3 -m unittest discover -s Tests/Tooling -v

# One local/CI gate. XCTest hosts are separate from the protected Release acceptance copy.
validate: tooling-test
	$(MAKE) test TEST_CONFIGURATION=Debug
	$(MAKE) test TEST_CONFIGURATION=Release
	$(MAKE) smoke

run: build
	open "$(DERIVED_DATA)/Build/Products/Release/Lisiere.app"
