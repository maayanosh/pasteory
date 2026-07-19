# NOTE: SwiftPM on this machine's CommandLineTools is broken (mismatched
# PackageDescription swiftmodule vs dylib -> every manifest fails to link),
# so we drive swiftc directly. Package.swift is kept for healthy toolchains.
# (A second CLT defect — a stale usr/include/swift/module.modulemap dupli-
# cating bridging.modulemap's SwiftBridging module — was fixed on 2026-07-05
# by renaming it to module.modulemap.bak.)

SWIFTC = swiftc
# Opt-in strict concurrency diagnostics: `make STRICT=1 …`. The sources are
# annotated with @MainActor/Sendable; complete checking surfaces data-race
# diagnostics as warnings on current toolchains, but some older compilers
# (e.g. Xcode 15's Swift 5.10) escalate a few of them to errors, so it stays
# off by default.
SWIFT_FLAGS = -swift-version 5
ifeq ($(STRICT),1)
SWIFT_FLAGS += -strict-concurrency=complete
endif
KIT_SRC := $(shell find Sources/PasteCloneKit -name '*.swift')
TEST_SRC := $(shell find Tests/PasteCloneKitTests -name '*.swift')
APP = build/Clap.app
ICONSET = build/AppIcon.iconset

all: bundle

build/PasteClone: $(KIT_SRC) Sources/PasteClone/main.swift
	mkdir -p build
	$(SWIFTC) -O $(SWIFT_FLAGS) -module-name PasteClone \
	  $(KIT_SRC) Sources/PasteClone/main.swift -o build/PasteClone

build: build/PasteClone

build/PasteCloneTests: $(KIT_SRC) $(TEST_SRC)
	mkdir -p build
	$(SWIFTC) $(SWIFT_FLAGS) -parse-as-library -module-name PasteCloneTests \
	  $(KIT_SRC) $(TEST_SRC) -o build/PasteCloneTests

test: build/PasteCloneTests
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

# Distributable disk image: Clap.app plus an /Applications symlink for
# drag-to-install. Ad-hoc signed — users must right-click → Open on first
# launch (or the DMG must be notarized with a Developer ID for a clean run).
DMG = build/Clap.dmg
dmg: bundle
	rm -rf build/dmg-staging $(DMG)
	mkdir -p build/dmg-staging
	cp -R $(APP) build/dmg-staging/
	ln -s /Applications build/dmg-staging/Applications
	hdiutil create -volname "Clap" -srcfolder build/dmg-staging -ov -format UDZO $(DMG)

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
