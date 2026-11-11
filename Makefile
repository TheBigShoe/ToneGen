SCHEME        = Tonegen
SIMULATOR     = platform=iOS Simulator,name=iPhone 17 Pro
XCARGS        = -scheme $(SCHEME) -destination '$(SIMULATOR)'

.PHONY: build test lint format generate clean

generate:
	xcodegen generate

build: generate
	xcodebuild $(XCARGS) -configuration Debug build

test: generate
	xcodebuild $(XCARGS) test

lint:
	swiftlint

format:
	swiftformat .

clean:
	xcodebuild $(XCARGS) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/Tonegen-*
