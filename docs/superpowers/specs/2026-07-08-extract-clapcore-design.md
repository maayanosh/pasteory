# Extract `ClapCore` — a platform-agnostic shared core

**Date:** 2026-07-08
**Status:** Approved (design)
**Branch:** `extract-clapcore`

## Goal & scope

Refactor the portable logic out of `PasteCloneKit` into a new, dependency-free,
platform-agnostic Swift module **`ClapCore`** that imports only `Foundation`
(plus `Observation`). Define the OS-specific behavior — clipboard capture, paste
injection, global hotkey, launch-at-login, source-app identity — as **protocols**
in the core. The macOS app implements those protocols with its existing
AppKit/Carbon code.

This is the honest prerequisite that makes a future Windows (or Linux) front-end
possible without touching core logic. It is the first sub-project of a larger
"cross-platform support" effort; shipping an actual Windows app is a separate,
later sub-project with its own spec.

### Non-goals

- **No Windows code ships in this step.** No Windows UI, clipboard, hotkey, or
  paste implementation. This step only creates the seams they would plug into.
- **No behavior change on macOS.** The app must behave identically to today:
  capture, ⇧⌘V panel, type-to-search, quick-paste (⌘1–9), pinboards,
  paste-in-place, Quick Look, dedup, privacy skip markers.
- **No unrelated refactoring.** Only the changes required to carve out the core
  and rewire the macOS layer through the seams.

## Module structure

```
Sources/
  ClapCore/                    # NEW: Foundation + Observation only.
                               # No AppKit / SwiftUI / Combine / Carbon / CryptoKit.
    Models.swift               # moved from PasteCloneKit; CryptoKit -> vendored SHA256
    SHA256.swift               # NEW: vendored pure-Swift SHA-256 (preserves existing hashes)
    Palette.swift              # palette + hex(for:) + luminance + rgb(fromHex:) moved from AppColors
    Store.swift                # moved; Combine ObservableObject -> @Observable
    Settings.swift             # moved; ServiceManagement removed (-> LaunchAtLoginController seam)
    SelectionState.swift       # pure filter/selection/multi-select logic from AppState
    Platform.swift             # NEW: the seam protocols

  PasteCloneKit/               # macOS-only glue; depends on ClapCore
    AppColors.swift            # keeps only the SwiftUI `Color(hex:)` extension (delegates to ClapCore.Palette)
    AppState.swift             # thin @Observable wrapper: owns Store/Settings/SelectionState + macOS seam impls
    ClipboardMonitor.swift     # conforms to ClipboardSource
    PasteService.swift         # conforms to Paster
    HotKey.swift               # conforms to GlobalHotKey
    LaunchAtLogin+macOS.swift  # NEW: ServiceManagement impl of LaunchAtLoginController
    UI/, PanelController, AppDelegate, ImageProcessor, ImageCache, IconCache  # unchanged
```

## Platform seams (`Sources/ClapCore/Platform.swift`)

```swift
/// Copies an item to the OS clipboard and pastes it into the previously
/// focused app. macOS impl: NSPasteboard write + focus restore + synthetic ⌘V.
public protocol Paster {
    func copy(_ item: ClipItem, plainText: Bool)
    func paste(_ item: ClipItem, plainText: Bool)
}

/// Watches the OS clipboard and emits captured items. macOS impl: NSPasteboard
/// change-count polling on a timer.
public protocol ClipboardSource: AnyObject {
    func start()
    func stop()
    var onCapture: ((ClipItem) -> Void)? { get set }
}

/// Registers the global show/hide chord. macOS impl: Carbon RegisterEventHotKey.
public protocol GlobalHotKey: AnyObject {
    func register(_ handler: @escaping () -> Void)
}

/// Registers/unregisters the app as a login item. macOS impl: ServiceManagement.
public protocol LaunchAtLoginController {
    func setEnabled(_ enabled: Bool)
}
```

Wiring:

- `SelectionState`'s paste actions call an injected `Paster`.
- `Store`'s capture pipeline is fed by an injected `ClipboardSource` (its
  `onCapture` closure calls `store.insert`).
- `Settings.launchAtLogin` change calls an injected `LaunchAtLoginController`.
- The core never names AppKit, Carbon, ServiceManagement, or SwiftUI.

## Key mechanical changes

### Observation model

`Store`, `Settings`, and the new `SelectionState` move from Combine
`ObservableObject`/`@Published` to `@Observable` (the Observation module, part of
the open-source Swift toolchain, so it compiles on non-Apple platforms). SwiftUI
on macOS 14+ consumes `@Observable` types natively.

SwiftUI views switch `@ObservedObject` / `@EnvironmentObject` →
`@Environment` / `@Bindable` as required. `AppState` becomes a thin `@Observable`
container that owns the core `Store` / `Settings` / `SelectionState` and holds the
macOS seam implementations.

**Alternative considered:** keep the core fully UI-neutral (no Observation),
exposing change notifications via `AsyncStream`/callbacks, with a macOS
`ObservableObject` adapter. Rejected: more plumbing for no benefit, since
Observation is already portable and SwiftUI consumes it directly.

### SHA-256

Vendor a pure-Swift SHA-256 into `ClapCore/SHA256.swift`. `ContentHasher` (in
`Models.swift`) calls it instead of `CryptoKit.SHA256`. The output is byte-for-byte
identical to CryptoKit's, so existing `store.json` `contentHash` values remain
valid and dedup keeps working across the upgrade. Keeps the project's
"no third-party dependencies" promise.

### AppColors split

- Pure data/math → `ClapCore/Palette.swift`: the 16-hue `palette`, `overrides`,
  `hex(for:)`, `luminance(ofHex:)`, `rgb(fromHex:)`.
- SwiftUI-only → stays in `PasteCloneKit/AppColors.swift`: the
  `Color(hex:)` extension and `Palette.color(for:)`-style helpers that produce
  `SwiftUI.Color`, delegating their math to `ClapCore.Palette`.

### Build

- `Package.swift`: add a `ClapCore` target with no dependencies; make
  `PasteCloneKit` depend on `ClapCore`; add a `ClapCoreTests` target.
- **Makefile (load-bearing build path):** the `swiftc` invocation compiles the
  whole app as one module list. Add the `Sources/ClapCore/*.swift` files to that
  list (ordering handled by the compiler within a single module invocation).
  This must be updated and verified with `make bundle` / `make open`, not just
  `swift build`.

## Testing & verification

- Move the tests covering pure core types (filter/selection logic, color
  parsing, dedup/insert behavior) from `Tests/PasteCloneKitTests` into a new
  `Tests/ClapCoreTests` target so the core is tested without AppKit. Keep
  macOS-integration tests where they are.
- **New test:** the vendored SHA-256 matches known published test vectors, and
  matches the previous CryptoKit output for representative inputs (locks in
  hash compatibility so stored dedup history is preserved).
- **Acceptance criteria:**
  - `make test` is green.
  - `make open` launches and the app behaves identically: clipboard capture,
    ⇧⌘V panel open/close, type-to-search, ← / → selection, Return paste-in-place,
    ⌘1–9 quick paste, pinboard create/move, dedup, concealed-type skip.
  - Verified by a real launch (use `PASTECLONE_SHOW_ON_LAUNCH=1` for scripted
    verification), not by tests alone.

## Delivery

- All work on branch `extract-clapcore`.
- Open a pull request against `main` when the implementation is complete and the
  acceptance criteria above are verified.
