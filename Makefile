# NOTE: SwiftPM on this machine's CommandLineTools is broken (mismatched
# PackageDescription swiftmodule vs dylib -> every manifest fails to link),
# so we drive swiftc directly. Package.swift is kept for healthy toolchains.
# (A second CLT defect — a stale usr/include/swift/module.modulemap dupli-
# cating bridging.modulemap's SwiftBridging module — was fixed on 2026-07-05
# by renaming it to module.modulemap.bak.)

SWIFTC = swiftc
CORE_SRC := $(shell find Sources/ClapCore -name '*.swift')
KIT_SRC := $(shell find Sources/PasteCloneKit -name '*.swift')
TEST_SRC := $(shell find Tests/PasteCloneKitTests -name '*.swift')
CORE_TEST_SRC := $(shell find Tests/ClapCoreTests -name '*.swift' 2>/dev/null)
APP = build/Clap.app
ICONSET = build/AppIcon.iconset

all: bundle

build/PasteClone: $(CORE_SRC) $(KIT_SRC) Sources/PasteClone/main.swift
	mkdir -p build
	$(SWIFTC) -O -swift-version 5 -module-name PasteClone \
	  $(CORE_SRC) $(KIT_SRC) Sources/PasteClone/main.swift -o build/PasteClone

build: build/PasteClone

build/PasteCloneTests: $(CORE_SRC) $(KIT_SRC) $(CORE_TEST_SRC) $(TEST_SRC)
	mkdir -p build
	$(SWIFTC) -swift-version 5 -parse-as-library -module-name PasteCloneTests \
	  $(CORE_SRC) $(KIT_SRC) $(CORE_TEST_SRC) $(TEST_SRC) -o build/PasteCloneTests

# Enforces core purity: SwiftPM is broken locally and the Makefile compiles
# everything as one module, so the compiler can't catch a forbidden import
# inside ClapCore. This grep guard does.
check-core:
	@! grep -REn 'import (AppKit|SwiftUI|Combine|Carbon|ServiceManagement|CryptoKit)' Sources/ClapCore \
	  || (echo "ERROR: forbidden import in Sources/ClapCore (see above)"; exit 1)
	@echo "core boundary OK"

test: check-core build/PasteCloneTests
	./build/PasteCloneTests

bundle: build/PasteClone
	# Assemble from scratch: once the app has been launched, macOS stamps it
	# with SIP-protected com.apple.provenance xattrs that xattr can't clear
	# and codesign rejects as detritus.
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp build/PasteClone $(APP)/Contents/MacOS/Clap
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	xattr -cr $(APP)   # sips/iconutil leave xattrs codesign rejects as "detritus"
	codesign --force --deep --sign - $(APP)

run: bundle
	$(APP)/Contents/MacOS/Clap

open: bundle
	open $(APP)

kill:
	pkill -x Clap || true

# Regenerates Resources/AppIcon.icns from the drawing script. Only needed
# when scripts/make-icon.swift changes; the .icns is committed.
icon: scripts/make-icon.swift
	mkdir -p build $(ICONSET)
	$(SWIFTC) scripts/make-icon.swift -o build/make-icon
	./build/make-icon build/icon-1024.png
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s build/icon-1024.png --out $(ICONSET)/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) build/icon-1024.png --out $(ICONSET)/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o Resources/AppIcon.icns

clean:
	rm -rf build .build
