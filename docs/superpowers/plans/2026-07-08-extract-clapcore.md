# ClapCore Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carve the portable logic out of `PasteCloneKit` into a new dependency-free `ClapCore` module with protocol seams for OS-specific behavior, leaving macOS behavior identical.

**Architecture:** New `ClapCore` target imports only `Foundation` + `Observation`. OS-specific behavior (clipboard capture, paste, global hotkey, launch-at-login) is expressed as protocols in the core and implemented by the existing AppKit/Carbon code in `PasteCloneKit`. Observable model types migrate from Combine `ObservableObject` to `@Observable` so they compile off-Apple.

**Tech Stack:** Swift 6 toolchain (compiling in Swift 5 language mode), SwiftUI/AppKit (macOS layer only), custom lightweight test harness (not XCTest), Makefile-driven `swiftc` build.

## Global Constraints

- **Build reality:** The Makefile compiles ALL sources as ONE module via a single `swiftc` invocation; SwiftPM (`swift build`) is broken on this machine. `make test` and `make bundle`/`make open` are the only valid local verification. Never claim verification from `swift build`.
- **Import guarding:** Every `import ClapCore` in `PasteCloneKit`/`PasteClone` sources MUST be wrapped `#if canImport(ClapCore)` / `#endif`, matching the existing `import PasteCloneKit` pattern in `main.swift`. In the one-module Makefile build `canImport(ClapCore)` is false and symbols resolve within the single module; under SwiftPM it is a real module.
- **Core purity:** `Sources/ClapCore/*.swift` may import ONLY `Foundation` and `Observation`. Forbidden: `AppKit`, `SwiftUI`, `Combine`, `Carbon`, `ServiceManagement`, `CryptoKit`. Enforced by the `make check-core` grep guard (Task 1), not the compiler.
- **No behavior change on macOS:** capture, ⇧⌘V panel, type-to-search, ←/→ selection, Return paste-in-place, ⇧+Return plain-text paste, ⌘C copy-back, ⌘1–9 quick paste, ⌘-click multi-select, ⌘R rename, Space Quick Look, ⇧⌘N pinboard, Delete, Esc, dedup, concealed-type skip, exclude-list — all must work identically.
- **Hash compatibility:** vendored SHA-256 output must be byte-for-byte identical to CryptoKit's, so existing `~/Library/Application Support/PasteClone/store.json` `contentHash` values stay valid.
- **Commit granularity:** commit after every task with a message describing the deliverable. End every commit message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Scaffold `ClapCore` + build wiring + boundary guard

**Files:**
- Create: `Sources/ClapCore/CoreVersion.swift`
- Modify: `Makefile` (source globs, `check-core` target)
- Modify: `Package.swift` (add target + test target + dependency)

**Interfaces:**
- Produces: an empty-but-buildable `ClapCore` module; `make check-core` guard; Makefile compiling `Sources/ClapCore/*.swift` into the app and test binaries.

- [ ] **Step 1: Create a trivial core file** so the module is non-empty.

`Sources/ClapCore/CoreVersion.swift`:
```swift
import Foundation

/// Marks the platform-agnostic core module. Bump when the core's public
/// surface changes in a way front-ends must know about.
public enum ClapCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 2: Wire the Makefile.** Add a `CORE_SRC` glob and include it in the app build, the test build, and a new `check-core` guard. Apply this diff:

Replace lines 8–10 (`SWIFTC = swiftc` … `TEST_SRC := …`) with:
```makefile
SWIFTC = swiftc
CORE_SRC := $(shell find Sources/ClapCore -name '*.swift')
KIT_SRC := $(shell find Sources/PasteCloneKit -name '*.swift')
TEST_SRC := $(shell find Tests/PasteCloneKitTests -name '*.swift')
CORE_TEST_SRC := $(shell find Tests/ClapCoreTests -name '*.swift' 2>/dev/null)
```

Change the app build recipe (currently lines 16–19) to prepend `$(CORE_SRC)`:
```makefile
build/PasteClone: $(CORE_SRC) $(KIT_SRC) Sources/PasteClone/main.swift
	mkdir -p build
	$(SWIFTC) -O -swift-version 5 -module-name PasteClone \
	  $(CORE_SRC) $(KIT_SRC) Sources/PasteClone/main.swift -o build/PasteClone
```

Change the test build recipe (currently lines 23–26) to include core + core tests:
```makefile
build/PasteCloneTests: $(CORE_SRC) $(KIT_SRC) $(CORE_TEST_SRC) $(TEST_SRC)
	mkdir -p build
	$(SWIFTC) -swift-version 5 -parse-as-library -module-name PasteCloneTests \
	  $(CORE_SRC) $(KIT_SRC) $(CORE_TEST_SRC) $(TEST_SRC) -o build/PasteCloneTests
```

Add a `check-core` target (place after the `test:` target) and make it a prerequisite of `test`:
```makefile
# Enforces core purity: SwiftPM is broken locally and the Makefile compiles
# everything as one module, so the compiler can't catch a forbidden import
# inside ClapCore. This grep guard does.
check-core:
	@! grep -REn 'import (AppKit|SwiftUI|Combine|Carbon|ServiceManagement|CryptoKit)' Sources/ClapCore \
	  || (echo "ERROR: forbidden import in Sources/ClapCore (see above)"; exit 1)
	@echo "core boundary OK"
```
Change the `test:` line from `test: build/PasteCloneTests` to:
```makefile
test: check-core build/PasteCloneTests
	./build/PasteCloneTests
```

- [ ] **Step 3: Update `Package.swift`** for healthy SwiftPM toolchains (not used locally but kept correct):
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PasteClone",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClapCore"),
        .target(name: "PasteCloneKit", dependencies: ["ClapCore"]),
        .executableTarget(name: "PasteClone", dependencies: ["PasteCloneKit"]),
        .testTarget(name: "ClapCoreTests", dependencies: ["ClapCore"]),
        .testTarget(name: "PasteCloneKitTests", dependencies: ["PasteCloneKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
```

- [ ] **Step 4: Verify the guard and build.**

Run: `make check-core`
Expected: `core boundary OK`

Run: `make test`
Expected: existing suite runs and prints its pass summary (unchanged from before).

Run: `make bundle`
Expected: builds `build/Clap.app` with no errors (deprecation warning about `UTTypeConformsTo` is pre-existing and OK).

- [ ] **Step 5: Commit**
```bash
git add Sources/ClapCore/CoreVersion.swift Makefile Package.swift
git commit -m "build: scaffold ClapCore module + core-boundary guard

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Vendor a pure-Swift SHA-256 in `ClapCore`

**Files:**
- Create: `Sources/ClapCore/SHA256.swift`
- Create: `Tests/ClapCoreTests/SHA256Tests.swift`
- Modify: `Tests/PasteCloneKitTests/TestMain.swift` (register the new test group)

**Interfaces:**
- Produces: `func clapSHA256Hex(_ data: Data) -> String` — lowercase hex of the SHA-256 digest, identical to `CryptoKit.SHA256`.

- [ ] **Step 1: Write the failing test** using published NIST vectors (these are exactly what CryptoKit produces, so they lock compatibility).

`Tests/ClapCoreTests/SHA256Tests.swift`:
```swift
import Foundation

@MainActor
func sha256Tests() {
    test("empty input matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
    test("\"abc\" matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    test("448-bit message matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }
    test("multi-block message matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data(String(repeating: "a", count: 1_000_000).utf8)),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}
```

- [ ] **Step 2: Register the group.** In `Tests/PasteCloneKitTests/TestMain.swift`, add a call to `sha256Tests()` alongside the existing group calls (e.g. after `modelsTests()`).

- [ ] **Step 3: Run to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'clapSHA256Hex' in scope`.

- [ ] **Step 4: Implement the vendored SHA-256.**

`Sources/ClapCore/SHA256.swift`:
```swift
import Foundation

/// Minimal, dependency-free SHA-256 (FIPS 180-4). Output is byte-for-byte
/// identical to CryptoKit's SHA256, so content hashes survive the migration.
public func clapSHA256Hex(_ data: Data) -> String {
    clapSHA256Digest(data).map { String(format: "%02x", $0) }.joined()
}

/// The 32-byte digest.
public func clapSHA256Digest(_ message: Data) -> [UInt8] {
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
    var h: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    var msg = [UInt8](message)
    let bitLen = UInt64(msg.count) * 8
    msg.append(0x80)
    while msg.count % 64 != 56 { msg.append(0) }
    for i in stride(from: 56, through: 0, by: -8) {
        msg.append(UInt8((bitLen >> UInt64(i)) & 0xff))
    }

    func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    for chunkStart in stride(from: 0, to: msg.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let j = chunkStart + i * 4
            w[i] = (UInt32(msg[j]) << 24) | (UInt32(msg[j + 1]) << 16)
                 | (UInt32(msg[j + 2]) << 8) | UInt32(msg[j + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i-15], 7) ^ rotr(w[i-15], 18) ^ (w[i-15] >> 3)
            let s1 = rotr(w[i-2], 17) ^ rotr(w[i-2], 19) ^ (w[i-2] >> 10)
            w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
            let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = S0 &+ maj
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }

    var out = [UInt8]()
    for word in h {
        out.append(UInt8((word >> 24) & 0xff))
        out.append(UInt8((word >> 16) & 0xff))
        out.append(UInt8((word >> 8) & 0xff))
        out.append(UInt8(word & 0xff))
    }
    return out
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `make test`
Expected: PASS — all four SHA-256 vectors match.

- [ ] **Step 6: Commit**
```bash
git add Sources/ClapCore/SHA256.swift Tests/ClapCoreTests/SHA256Tests.swift Tests/PasteCloneKitTests/TestMain.swift
git commit -m "feat(core): vendor pure-Swift SHA-256 with NIST-vector tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Move `Models` into `ClapCore`, switch `ContentHasher` off CryptoKit

**Files:**
- Move: `Sources/PasteCloneKit/Models.swift` → `Sources/ClapCore/Models.swift`
- Move: `Tests/PasteCloneKitTests/ModelsTests.swift` → `Tests/ClapCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `clapSHA256Hex(_:)` from Task 2.
- Produces: `ClipItem`, `ClipKind`, `Pinboard`, `ContentHasher`, `ParsedColor`, `parseColorString`, `isLinkString`, `relativeTimeString`, `looksLikeCode` — now in `ClapCore` (public surface unchanged).

- [ ] **Step 1: Move the model file.**
```bash
git mv Sources/PasteCloneKit/Models.swift Sources/ClapCore/Models.swift
git mv Tests/PasteCloneKitTests/ModelsTests.swift Tests/ClapCoreTests/ModelsTests.swift
```

- [ ] **Step 2: Switch `ContentHasher` to the vendored hash.** In `Sources/ClapCore/Models.swift`, change the top import and the hasher body:

Replace `import Foundation` / `import CryptoKit` (lines 1–2) with just:
```swift
import Foundation
```
Replace the `ContentHasher.hash(_ data:)` body:
```swift
public enum ContentHasher {
    public static func hash(_ data: Data) -> String {
        clapSHA256Hex(data)
    }

    public static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }
}
```

- [ ] **Step 3: Run to verify** the boundary guard and existing model/dedup tests still pass with the new hash.

Run: `make test`
Expected: PASS — `check-core` prints `core boundary OK`; `ModelsTests` (including any content-hash assertions) pass.

- [ ] **Step 4: Verify hash compatibility against real data.** Confirm the dedup hash for a known string is unchanged from CryptoKit:

Run: `printf 'text:hello' | shasum -a 256`
Expected: `f68c...` — note the value, then confirm the app produces the same by checking a `ModelsTests` assertion that `ContentHasher.hash("text:hello")` equals that hex. If `ModelsTests` lacks such an assertion, add one in this step:
```swift
test("content hash is standard SHA-256 (dedup compatibility)") {
    expectEqual(ContentHasher.hash("text:hello"),
        "f68c113b21b04b78b4b3f8f9a9b3a2b3c... (use `printf 'text:hello' | shasum -a 256`)")
}
```
Replace the placeholder hex with the exact output of the `shasum` command above before committing.

- [ ] **Step 5: Commit**
```bash
git add -A
git commit -m "refactor(core): move Models into ClapCore, hash via vendored SHA-256

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Extract `Palette` into `ClapCore`, slim `AppColors`

**Files:**
- Create: `Sources/ClapCore/Palette.swift`
- Modify: `Sources/PasteCloneKit/AppColors.swift` (keep only SwiftUI glue)
- Move: `Tests/PasteCloneKitTests/AppColorsTests.swift` → `Tests/ClapCoreTests/PaletteTests.swift`

**Interfaces:**
- Produces: `enum Palette` with `palette: [String]`, `hex(for:) -> String`, `luminance(ofHex:) -> Double`, `rgb(fromHex:) -> (Double, Double, Double)`.
- `AppColors` keeps `color(for:) -> Color` and the `Color(hex:)` extension, delegating math to `Palette`.

- [ ] **Step 1: Create the pure palette in core.**

`Sources/ClapCore/Palette.swift`:
```swift
import Foundation

/// Pure color math shared across platforms. No UI-framework colors here.
public enum Palette {
    public static let palette: [String] = [
        "#4A90D9", "#E8734A", "#4CAF6E", "#A550A7", "#E8B93E", "#4CC2E8",
        "#E85C5C", "#3AB5A0", "#5E5CE6", "#8FBE4F", "#E06C9F", "#A97B54",
        "#9B8CE8", "#6E8CA0", "#2E7D5B", "#3C3C43",
    ]

    static let overrides: [String: String] = [
        "com.apple.Safari": "#4A90D9",
        "com.google.Chrome": "#E8734A",
        "com.apple.finder": "#4CC2E8",
        "com.apple.Notes": "#E8B93E",
        "com.microsoft.VSCode": "#5E5CE6",
        "com.tinyspeck.slackmacgap": "#A550A7",
        "com.apple.Terminal": "#3C3C43",
        "com.googlecode.iterm2": "#2E7D5B",
        "com.apple.mail": "#3AB5A0",
        "com.apple.dt.Xcode": "#6E8CA0",
    ]

    /// Stable across launches (djb2 over UTF-8; Swift's hashValue is seeded).
    public static func hex(for bundleID: String?) -> String {
        guard let id = bundleID, !id.isEmpty else { return "#3C3C43" }
        if let fixed = overrides[id] { return fixed }
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }

    public static func luminance(ofHex hex: String) -> Double {
        let (r, g, b) = rgb(fromHex: hex)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    public static func rgb(fromHex hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return (0, 0, 0) }
        return (
            Double((v >> 16) & 0xFF) / 255.0,
            Double((v >> 8) & 0xFF) / 255.0,
            Double(v & 0xFF) / 255.0
        )
    }
}
```

- [ ] **Step 2: Slim `AppColors` to SwiftUI glue only.** Replace the entire contents of `Sources/PasteCloneKit/AppColors.swift` with:
```swift
import SwiftUI
#if canImport(ClapCore)
import ClapCore
#endif

public enum AppColors {
    public static var palette: [String] { Palette.palette }
    public static func hex(for bundleID: String?) -> String { Palette.hex(for: bundleID) }
    public static func luminance(ofHex hex: String) -> Double { Palette.luminance(ofHex: hex) }

    public static func color(for bundleID: String?) -> Color {
        Color(hex: hex(for: bundleID))
    }
}

public extension Color {
    init(hex: String) {
        let (r, g, b) = Palette.rgb(fromHex: hex)
        self.init(red: r, green: g, blue: b)
    }
}
```
(The `AppColors.palette`/`hex`/`luminance` forwarders keep existing call sites in the UI unchanged.)

- [ ] **Step 3: Move the palette tests to core and retarget them at `Palette`.**
```bash
git mv Tests/PasteCloneKitTests/AppColorsTests.swift Tests/ClapCoreTests/PaletteTests.swift
```
In `Tests/ClapCoreTests/PaletteTests.swift`, rename the function `appColorsTests` → `paletteTests`, and replace every `AppColors.` with `Palette.`. Then update the call in `TestMain.swift` from `appColorsTests()` to `paletteTests()`.

- [ ] **Step 4: Run to verify**

Run: `make test`
Expected: PASS — `core boundary OK`; palette tests (overrides, determinism, uniqueness, luminance) pass.

Run: `make bundle`
Expected: builds with no errors (card headers/tabs still compile against `AppColors`/`Color(hex:)`).

- [ ] **Step 5: Commit**
```bash
git add -A
git commit -m "refactor(core): extract Palette into ClapCore, slim AppColors to SwiftUI glue

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Define the platform seam protocols in `ClapCore`

**Files:**
- Create: `Sources/ClapCore/Platform.swift`

**Interfaces:**
- Produces: protocols `Paster`, `ClipboardSource`, `GlobalHotKey`, `LaunchAtLoginController` (consumed by Tasks 6–9). No existing code changes, so nothing can break.

- [ ] **Step 1: Create the seam file.**

`Sources/ClapCore/Platform.swift`:
```swift
import Foundation

/// Copies an item to the OS clipboard and pastes it into the previously
/// focused app. macOS impl: NSPasteboard write + focus restore + synthetic ⌘V.
@MainActor
public protocol Paster: AnyObject {
    func copy(_ item: ClipItem, plainText: Bool)
    func paste(_ item: ClipItem, plainText: Bool)
}

/// Watches the OS clipboard and emits captured items. macOS impl: NSPasteboard
/// change-count polling on a timer.
@MainActor
public protocol ClipboardSource: AnyObject {
    var onCapture: ((ClipItem) -> Void)? { get set }
    func start()
    func stop()
}

/// Registers the global show/hide chord. macOS impl: Carbon RegisterEventHotKey.
@MainActor
public protocol GlobalHotKey: AnyObject {
    func register(_ handler: @escaping () -> Void)
}

/// Registers/unregisters the app as a login item. macOS impl: ServiceManagement.
@MainActor
public protocol LaunchAtLoginController {
    func setEnabled(_ enabled: Bool)
}
```

- [ ] **Step 2: Verify it compiles and the guard passes.**

Run: `make test`
Expected: PASS — `core boundary OK`; suite unchanged.

- [ ] **Step 3: Commit**
```bash
git add Sources/ClapCore/Platform.swift
git commit -m "feat(core): add platform seam protocols (Paster, ClipboardSource, GlobalHotKey, LaunchAtLoginController)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Migrate `Settings` to `@Observable`, move to core, add macOS login-item impl

**Files:**
- Move: `Sources/PasteCloneKit/Settings.swift` → `Sources/ClapCore/Settings.swift`
- Create: `Sources/PasteCloneKit/LaunchAtLogin+macOS.swift`
- Modify: `Sources/PasteCloneKit/AppDelegate.swift` (inject login-item controller)
- Modify: `Sources/PasteCloneKit/UI/SettingsView.swift` (Observation binding)

**Interfaces:**
- Consumes: `LaunchAtLoginController` (Task 5).
- Produces: `@Observable @MainActor final class Settings` in `ClapCore` with the same stored properties (`isPaused`, `excludedBundleIDs`, `historyLimit`, `launchAtLogin`, `panelOpacity`) and `init(defaults:launchAtLogin:)`. macOS type `MacLaunchAtLogin: LaunchAtLoginController`.

- [ ] **Step 1: Move the file.**
```bash
git mv Sources/PasteCloneKit/Settings.swift Sources/ClapCore/Settings.swift
```

- [ ] **Step 2: Rewrite `Settings` to `@Observable` with an injected controller.** Replace the contents of `Sources/ClapCore/Settings.swift` with:
```swift
import Foundation
import Observation

@Observable
@MainActor
public final class Settings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginController: LaunchAtLoginController?

    public var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    public var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    public var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            loginController?.setEnabled(launchAtLogin)
        }
    }
    /// Panel background opacity, 0.3...1.0.
    public var panelOpacity: Double { didSet { defaults.set(panelOpacity, forKey: "panelOpacity") } }

    public init(defaults: UserDefaults = .standard, loginController: LaunchAtLoginController? = nil) {
        self.defaults = defaults
        self.loginController = loginController
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        let limit = defaults.integer(forKey: "historyLimit")
        self.historyLimit = limit == 0 ? 500 : limit
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        let opacity = defaults.double(forKey: "panelOpacity")
        self.panelOpacity = opacity == 0 ? 0.85 : min(max(opacity, 0.3), 1.0)
    }
}
```

- [ ] **Step 3: Add the macOS login-item implementation.**

`Sources/PasteCloneKit/LaunchAtLogin+macOS.swift`:
```swift
import Foundation
import ServiceManagement
#if canImport(ClapCore)
import ClapCore
#endif

/// macOS login-item control via ServiceManagement. Only works from inside a
/// real .app bundle; failures during dev are logged and ignored.
public struct MacLaunchAtLogin: LaunchAtLoginController {
    public init() {}
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("PasteClone: launch-at-login change failed: \(error)")
        }
    }
}
```

- [ ] **Step 4: Inject the controller where `Settings` is constructed.** In `Sources/PasteCloneKit/AppDelegate.swift`, find the `Settings(...)` construction and pass the macOS controller:
```swift
let settings = Settings(loginController: MacLaunchAtLogin())
```
(If `Settings()` is currently built with no arguments, add the `loginController:` argument; keep any existing `defaults:` argument.)

- [ ] **Step 5: Update `SettingsView` for Observation.** In `Sources/PasteCloneKit/UI/SettingsView.swift`, change how `Settings` is held: replace `@ObservedObject var settings: Settings` (or `@EnvironmentObject`) with `@Bindable var settings: Settings` (for a passed-in instance) or `@Environment(Settings.self) private var settings` + a local `@Bindable var settings = settings` inside `body` where bindings (`$settings.panelOpacity`, toggles) are used. Keep the same controls and behavior.

- [ ] **Step 6: Run to verify**

Run: `make test`
Expected: PASS — `core boundary OK` (Settings no longer imports Combine/ServiceManagement); suite unchanged.

Run: `make bundle && PASTECLONE_SHOW_ON_LAUNCH=1 open build/Clap.app`
Expected: app launches; open Settings; toggling pause, changing history limit, and moving the opacity slider all work; toggling launch-at-login does not crash.

- [ ] **Step 7: Commit**
```bash
git add -A
git commit -m "refactor(core): migrate Settings to @Observable in ClapCore, add MacLaunchAtLogin seam impl

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Migrate `Store` to `@Observable`, move to core, drive capture via `ClipboardSource`

**Files:**
- Move: `Sources/PasteCloneKit/Store.swift` → `Sources/ClapCore/Store.swift`
- Move: `Tests/PasteCloneKitTests/StoreTests.swift` → `Tests/ClapCoreTests/StoreTests.swift`
- Modify: `Sources/PasteCloneKit/ClipboardMonitor.swift` (conform to `ClipboardSource`)

**Interfaces:**
- Consumes: `Palette` (Task 4, used in `addPinboard`), `ClipboardSource` (Task 5).
- Produces: `@Observable @MainActor final class Store` in `ClapCore`; `ClipboardMonitor: ClipboardSource` exposing `var onCapture`.

- [ ] **Step 1: Move the files.**
```bash
git mv Sources/PasteCloneKit/Store.swift Sources/ClapCore/Store.swift
git mv Tests/PasteCloneKitTests/StoreTests.swift Tests/ClapCoreTests/StoreTests.swift
```

- [ ] **Step 2: Migrate `Store` to `@Observable` and fix its `Palette` reference.** In `Sources/ClapCore/Store.swift`:

Replace the top imports (`import Foundation` / `import Combine`) with:
```swift
import Foundation
import Observation
```
Change the class declaration from
```swift
@MainActor
public final class Store: ObservableObject {
    @Published public private(set) var items: [ClipItem] = []
    @Published public private(set) var pinboards: [Pinboard] = []
```
to
```swift
@Observable
@MainActor
public final class Store {
    public private(set) var items: [ClipItem] = []
    public private(set) var pinboards: [Pinboard] = []
```
Mark the non-observable stored properties: add `@ObservationIgnored` before `public let directory: URL` and before `private var saveWorkItem: DispatchWorkItem?`.
In `addPinboard`, change `AppColors.palette` to `Palette.palette`:
```swift
let hex = Palette.palette[pinboards.count % Palette.palette.count]
```

- [ ] **Step 3: Conform `ClipboardMonitor` to `ClipboardSource`.** In `Sources/PasteCloneKit/ClipboardMonitor.swift`:

Add the ClapCore import under `import AppKit`:
```swift
import AppKit
#if canImport(ClapCore)
import ClapCore
#endif
```
Change the class to conform and to publish captures through `onCapture` instead of calling `store.insert` directly. Update the declaration:
```swift
public final class ClipboardMonitor: ClipboardSource {
    public var onCapture: ((ClipItem) -> Void)?
```
Remove the stored `private let store: Store` dependency used only for insertion, but KEEP the `store` reference it needs for writing content files (`store.contentURL`, `store.insert`). Since `buildItem` uses `store.contentURL(...)` and `ImageProcessor.makeItem(..., store: store, ...)`, keep `store` as a dependency for content-file writing, and replace the final `store.insert(item)` in `check()` with:
```swift
onCapture?(item)
```
Wire `onCapture` to `store.insert` at the construction site (Task 8, in `AppState`/`AppDelegate`).

- [ ] **Step 4: Run to verify**

Run: `make test`
Expected: PASS — `core boundary OK` (Store no longer imports Combine or AppColors/SwiftUI); `StoreTests` (insert/dedup/limit/pinboard) pass.

- [ ] **Step 5: Commit**
```bash
git add -A
git commit -m "refactor(core): migrate Store to @Observable in ClapCore, capture via ClipboardSource seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Extract `SelectionState` into core; reduce `AppState` to a thin `@Observable` container; wire seams

**Files:**
- Create: `Sources/ClapCore/SelectionState.swift`
- Modify: `Sources/PasteCloneKit/AppState.swift` (thin container)
- Modify: `Sources/PasteCloneKit/PasteService.swift` (conform to `Paster`)
- Modify: `Sources/PasteCloneKit/HotKey.swift` (conform to `GlobalHotKey`)
- Modify: `Sources/PasteCloneKit/AppDelegate.swift` (assemble via seams)
- Move: `Tests/PasteCloneKitTests/FilterTests.swift` → `Tests/ClapCoreTests/FilterTests.swift`

**Interfaces:**
- Consumes: `Paster`, `GlobalHotKey`, `ClipboardSource` (Task 5), `Store` (Task 7).
- Produces: `@Observable @MainActor final class SelectionState` in core with the pure query/selection/multi-select API and paste actions delegating to an injected `Paster`. Static `SelectionState.filter(items:tab:query:)` and `SelectionState.matches(_:query:)`.

- [ ] **Step 1: Create `SelectionState` in core** with the pure logic + `Paster`-delegating actions. `Sources/ClapCore/SelectionState.swift`:
```swift
import Foundation
import Observation

@Observable
@MainActor
public final class SelectionState {
    public var query = ""
    public var selectedTab: UUID?
    public var selectionID: UUID?
    public var multiSelection: Set<UUID> = []
    public var showNumbers = false
    public var searchFocused = false
    public var previewItem: ClipItem?

    @ObservationIgnored public let store: Store
    @ObservationIgnored public var paster: Paster?

    public init(store: Store) { self.store = store }

    // MARK: - Filtering (pure)
    public static func matches(_ item: ClipItem, query: String) -> Bool {
        let q = query.lowercased()
        if let text = item.text, text.lowercased().contains(q) { return true }
        if let app = item.sourceAppName, app.lowercased().contains(q) { return true }
        return item.kind.rawValue.lowercased().contains(q)
    }
    public static func filter(items: [ClipItem], tab: UUID?, query: String) -> [ClipItem] {
        items.filter { $0.pinboardID == tab }
            .filter { query.isEmpty || matches($0, query: query) }
    }
    public var filteredItems: [ClipItem] {
        Self.filter(items: store.items, tab: selectedTab, query: query)
    }

    public func panelDidShow() {
        query = ""; searchFocused = false; previewItem = nil
        selectedTab = nil; showNumbers = false; multiSelection = []
        selectionID = filteredItems.first?.id
    }

    public var selectedItem: ClipItem? {
        let visible = filteredItems
        guard let id = selectionID else { return visible.first }
        return visible.first { $0.id == id } ?? visible.first
    }
    public func moveSelection(by delta: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { return }
        guard let current = visible.firstIndex(where: { $0.id == selectionID }) else {
            selectionID = visible.first?.id; return
        }
        let next = min(max(current + delta, 0), visible.count - 1)
        selectionID = visible[next].id
    }
    public func ensureSelectionValid() {
        let visible = filteredItems
        if selectionID == nil || !visible.contains(where: { $0.id == selectionID }) {
            selectionID = visible.first?.id
        }
    }

    public func toggleMultiSelect(_ id: UUID) {
        if multiSelection.contains(id) { multiSelection.remove(id) } else { multiSelection.insert(id) }
    }
    public func clearMultiSelection() { multiSelection.removeAll() }
    public var orderedMultiSelection: [ClipItem] {
        guard !multiSelection.isEmpty else { return [] }
        return filteredItems.filter { multiSelection.contains($0.id) }
    }

    // MARK: - Actions (delegate to Paster)
    public func pasteSelected(plainText: Bool = false) {
        guard let item = selectedItem else { return }
        paster?.paste(item, plainText: plainText)
    }
    public func pasteMultiSelection(plainText: Bool = false) {
        let items = orderedMultiSelection
        guard !items.isEmpty else { return pasteSelected(plainText: plainText) }
        clearMultiSelection()
        pasteSequentially(items, index: 0, plainText: plainText)
    }
    private func pasteSequentially(_ items: [ClipItem], index: Int, plainText: Bool) {
        guard index < items.count else { return }
        paster?.paste(items[index], plainText: plainText)
        let next = index + 1
        guard next < items.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pasteSequentially(items, index: next, plainText: plainText)
        }
    }
    public func paste(at index: Int, plainText: Bool = false) {
        let visible = filteredItems
        guard visible.indices.contains(index) else { return }
        paster?.paste(visible[index], plainText: plainText)
    }
    public func copySelected() {
        guard let item = selectedItem else { return }
        paster?.copy(item, plainText: false)
    }
    public func deleteSelected() {
        guard let item = selectedItem else { return }
        let visible = filteredItems
        if let idx = visible.firstIndex(of: item) {
            let nextIdx = idx + 1 < visible.count ? idx + 1 : idx - 1
            selectionID = visible.indices.contains(nextIdx) ? visible[nextIdx].id : nil
        }
        store.delete(item.id)
        if previewItem?.id == item.id { previewItem = nil }
    }
    public func appendToQuery(_ chars: String) {
        query += chars; searchFocused = true; ensureSelectionValid()
    }
}
```

- [ ] **Step 2: Reduce `AppState` to a macOS-side container.** Replace the contents of `Sources/PasteCloneKit/AppState.swift` with a thin type that exposes the `SelectionState` and holds macOS objects the views still need (e.g. it keeps `settings`). It no longer imports Combine and no longer re-publishes store changes (Observation tracks nested `@Observable` automatically):
```swift
import AppKit
#if canImport(ClapCore)
import ClapCore
#endif

/// macOS-side glue: owns the core SelectionState + Store + Settings and the
/// AppKit seam implementations. Views read `app.selection`, `app.store`, etc.
@Observable
@MainActor
public final class AppState {
    public let selection: SelectionState
    public let settings: Settings
    public var store: Store { selection.store }

    public init(store: Store, settings: Settings, paster: Paster) {
        self.selection = SelectionState(store: store)
        self.settings = settings
        self.selection.paster = paster
    }
}
```
Then update UI references: anywhere a view previously called `appState.filteredItems`, `appState.selectionID`, `appState.pasteSelected()`, etc., route through `appState.selection.…`. Update the SwiftUI property wrappers from `@EnvironmentObject`/`@ObservedObject` to `@Environment(AppState.self)` + local `@Bindable` where two-way bindings are needed. Views touched: `PanelRootView`, `CardView`, `SearchBar`, `PinboardTabs`, `PreviewPopover`. Preserve behavior exactly.

- [ ] **Step 3: Conform `PasteService` to `Paster`.** In `Sources/PasteCloneKit/PasteService.swift`, add `import ClapCore` under a `#if canImport` guard, change the declaration to `public final class PasteService: Paster`, and make the two methods match the protocol signatures (`func copy(_:plainText:)` already matches once `plainText` loses its default in the protocol conformance — keep the concrete default by adding a protocol-satisfying overload if needed). Keep `previousApp`, `willPaste`, monitor dependency, and the AppKit body unchanged.

- [ ] **Step 4: Conform `HotKey` to `GlobalHotKey`.** In `Sources/PasteCloneKit/HotKey.swift`, add the guarded `import ClapCore`, change the declaration to conform to `GlobalHotKey`, and expose `func register(_ handler: @escaping () -> Void)` wrapping the existing Carbon registration (map the existing callback property to the protocol method).

- [ ] **Step 5: Assemble in `AppDelegate`.** In `Sources/PasteCloneKit/AppDelegate.swift`, build the graph via seams:
```swift
let settings = Settings(loginController: MacLaunchAtLogin())
let store = Store()
let monitor = ClipboardMonitor(store: store, settings: settings)
monitor.onCapture = { store.insert($0) }
let paste = PasteService(store: store, monitor: monitor)
let appState = AppState(store: store, settings: settings, paster: paste)
monitor.start()
```
Wire the hotkey registration to the panel toggle as before, using `hotKey.register { … toggle panel … }`. Keep the rest of `AppDelegate` (panel controller, activation policy) intact.

- [ ] **Step 6: Move filter tests to core and retarget at `SelectionState`.**
```bash
git mv Tests/PasteCloneKitTests/FilterTests.swift Tests/ClapCoreTests/FilterTests.swift
```
In the moved file, replace every `AppState.filter` / `AppState.matches` with `SelectionState.filter` / `SelectionState.matches`. Update the `TestMain.swift` group call if its name changes (keep `filterTests()`).

- [ ] **Step 7: Run to verify (tests + real launch).**

Run: `make test`
Expected: PASS — `core boundary OK` (SelectionState/Store/Settings/Models/Palette/SHA256/Platform in core, none importing AppKit/Combine/SwiftUI); filter/store/models/palette/sha256 tests pass.

Run: `make bundle && PASTECLONE_SHOW_ON_LAUNCH=1 open build/Clap.app`
Expected — exercise the full macOS surface and confirm identical behavior:
- Copy text/link/image/file/color in another app → cards appear, color-coded, dedup on re-copy.
- ⇧⌘V toggles the panel; type-to-search filters; ←/→ moves selection.
- Return pastes into the previous app; ⇧+Return pastes plain text; ⌘C copies back.
- Hold ⌘ shows 1–9 badges; ⌘1–9 quick-pastes; ⌘-click multi-selects and Return pastes in order.
- ⌘R rename, Space Quick Look, ⇧⌘N new pinboard + move items, Delete removes, Esc closes.

- [ ] **Step 8: Commit**
```bash
git add -A
git commit -m "refactor(core): extract SelectionState to ClapCore; thin AppState; wire Paster/GlobalHotKey/ClipboardSource seams

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Update docs to reflect the module split

**Files:**
- Modify: `README.md` (Development → Project layout section, lines ~100–113)

**Interfaces:** none.

- [ ] **Step 1: Update the project-layout block** in `README.md` to add the core module. Replace the layout list so it reads:
```
Sources/ClapCore/           Platform-agnostic core (models, store, settings, selection, palette, hashing, seam protocols)
Sources/PasteClone/         Executable entry point (main.swift)
Sources/PasteCloneKit/      macOS layer: AppKit/SwiftUI glue implementing ClapCore's platform seams
Sources/PasteCloneKit/UI/   SwiftUI views (cards, search bar, settings, pinboards)
Tests/ClapCoreTests/        Core unit tests (SHA-256, models, palette, filter, store)
Tests/PasteCloneKitTests/   macOS-layer unit test harness (not XCTest)
scripts/make-icon.swift     Draws the app icon (regenerate with `make icon`)
PLAN.md                     Design/research notes this project was built from
```
Add one sentence noting that `ClapCore` imports only Foundation/Observation and defines the `Paster`/`ClipboardSource`/`GlobalHotKey`/`LaunchAtLoginController` seams that a future non-macOS front-end would implement.

- [ ] **Step 2: Verify** the build is untouched and still green.

Run: `make test && make bundle`
Expected: PASS; app bundle builds.

- [ ] **Step 3: Commit**
```bash
git add README.md
git commit -m "docs: describe ClapCore module split and platform seams

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Goal & scope (dependency-free core, protocol seams, macOS unchanged) → Tasks 1–8. ✅
- Non-goals (no Windows code, no behavior change) → honored; Task 8 Step 7 verifies parity. ✅
- Module structure (ClapCore files, slimmed AppColors, macOS seam impls) → Tasks 3,4,6,7,8. ✅
- Platform seams → Task 5. ✅
- Observation migration → Tasks 6 (Settings), 7 (Store), 8 (SelectionState/AppState + views). ✅
- SHA-256 vendoring + hash compatibility → Task 2 + Task 3 Step 4. ✅
- AppColors split → Task 4. ✅
- Build (Package.swift + Makefile) → Task 1. ✅
- Testing (ClapCoreTests target, move core tests, SHA vectors, `make test`/launch acceptance) → Tasks 1,2,3,4,7,8. ✅
- Core-boundary enforcement → `make check-core` guard (Task 1), run in every `make test`. ✅
- Docs → Task 9. ✅

**Placeholder scan:** One deliberate fill-in remains — Task 3 Step 4 requires pasting the exact `shasum -a 256` output for `text:hello`; the step instructs computing and substituting it before commit. No other TBD/TODO.

**Type consistency:** `SelectionState.filter`/`.matches` (Task 8) match the test updates (Task 8 Step 6). `Paster.copy/paste(_:plainText:)`, `ClipboardSource.onCapture/start/stop`, `GlobalHotKey.register`, `LaunchAtLoginController.setEnabled` (Task 5) match their implementers (`PasteService`, `ClipboardMonitor`, `HotKey`, `MacLaunchAtLogin`) and call sites (`AppDelegate`, Tasks 6–8). `Settings.init(defaults:loginController:)` matches the `AppDelegate` construction. `Palette.palette/hex/luminance/rgb` match `AppColors` forwarders and `Store.addPinboard`.
