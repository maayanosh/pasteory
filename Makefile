# NOTE: SwiftPM on this machine's CommandLineTools is broken (mismatched
# PackageDescription swiftmodule vs dylib -> every manifest fails to link),
# so we drive swiftc directly. Package.swift is kept for healthy toolchains.
# (A second CLT defect — a stale usr/include/swift/module.modulemap dupli-
# cating bridging.modulemap's SwiftBridging module — was fixed on 2026-07-05
# by renaming it to module.modulemap.bak.)

SWIFTC = swiftc
KIT_SRC := $(shell find Sources/PasteCloneKit -name '*.swift')
TEST_SRC := $(shell find Tests/PasteCloneKitTests -name '*.swift')
APP = build/PasteClone.app

all: bundle

build/PasteClone: $(KIT_SRC) Sources/PasteClone/main.swift
	mkdir -p build
	$(SWIFTC) -O -swift-version 5 -module-name PasteClone \
	  $(KIT_SRC) Sources/PasteClone/main.swift -o build/PasteClone

build: build/PasteClone

build/PasteCloneTests: $(KIT_SRC) $(TEST_SRC)
	mkdir -p build
	$(SWIFTC) -swift-version 5 -parse-as-library -module-name PasteCloneTests \
	  $(KIT_SRC) $(TEST_SRC) -o build/PasteCloneTests

test: build/PasteCloneTests
	./build/PasteCloneTests

bundle: build/PasteClone
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp build/PasteClone $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	codesign --force --deep --sign - $(APP)

run: bundle
	$(APP)/Contents/MacOS/PasteClone

open: bundle
	open $(APP)

kill:
	pkill -x PasteClone || true

clean:
	rm -rf build .build
