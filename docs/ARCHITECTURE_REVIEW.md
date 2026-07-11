# Architecture Review — Clap (pasteory)

Date: 2026-07-11
Scope: full read of `Sources/`, `Tests/`, `Makefile`, `Resources/Info.plist`, `Package.swift`.

Overall: this is a well-written small codebase (~2,300 lines). Responsibilities are
mostly separated correctly (capture → store → state → UI), comments explain
non-obvious decisions, and the pure logic (filtering, color parsing, store
mutations) is unit-tested. The issues below are ordered by severity: first
things that lose data or freeze the UI, then robustness/design problems, then
structure and package layout improvements.

## Status — implemented on this branch

Fixed by the commits following this document:

- §1.1 versioned snapshot; background, logged saves; `flush()` on quit
- §1.2 image capture moved off the main thread onto ImageIO
- §1.3 startup sweep of orphaned content files
- §1.4 activation-confirmed ⌘V with timeout fallback; completion-chained multi-paste
- §1.5 `byteSize` captured on the model; cached file icons; async Settings data size
- §1.6 `historyLimit` owned by Settings, synced via one subscription
- §2.1 `PasteActions` protocol injection + `AppComposition` root
- §2.2 cached `filteredItems`
- §2.3 `PasteboardReading` seam + ClipboardMonitor test suite
- §2.4 `-strict-concurrency=complete` in the Makefile (§3.2 partially: CI workflow added,
  driving the Makefile build since `swift test` can't run the custom harness)
- §2.5 `files: [String]` stored on new items, legacy `text` form still decoded
- §2.6 dedup refreshes source-app metadata
- §2.7 `0700` data directory; atomic content-file writes
- §2.8 `UTType` instead of `UTTypeConformsTo`
- §3.4 shared `formatByteSize` + readable-text-color helpers
- Smaller items: timestamped corrupt backups, first-unused pinboard color,
  Settings sentinel reads, previews via `ImageCache`

Still open (deliberately deferred): §3.1 target split, SQLite storage (§1.1
long-term), §3.3 naming centralization, `looksLikeCode` tuning (its current
behavior is pinned by tests), Info.plist version stamping.

---

## 1. High severity — data integrity & responsiveness

### 1.1 Persistence failures are silent, and every save rewrites the whole store on the main thread

`Store.saveNow()` (`Sources/PasteCloneKit/Store.swift:47`) encodes the entire
history to JSON and writes it synchronously **on the main actor**, with all
errors swallowed by `try?`:

- If encoding or writing fails (disk full, sandbox, permissions), the user
  loses history with no log line and no UI signal.
- The file grows with history. Every card holds its full text in `store.json`;
  with the "Forever" limit (`SettingsView.swift:18`) the file is unbounded, and
  the 0.5 s debounced save plus the synchronous save in
  `PanelController.hidePanel()` (`PanelController.swift:107`) will visibly
  hitch the hide animation once the file reaches a few MB.
- `Snapshot` has **no schema version field**. Any future non-optional field
  addition makes old files undecodable, which triggers the
  `store.json.corrupt` path and effectively wipes the user's history.

**Fixes**
1. Add `var version: Int = 1` to `Snapshot` now, before any format change.
2. Encode + write on a background task; only the array snapshot needs to be
   taken on the main actor:
   ```swift
   public func saveNow() {
       let snapshot = Snapshot(items: items, pinboards: pinboards)
       let url = storeFile
       Task.detached(priority: .utility) {
           do {
               let data = try JSONEncoder().encode(snapshot)
               try data.write(to: url, options: .atomic)
           } catch {
               NSLog("Clap: store save failed: \(error)")
           }
       }
   }
   ```
   (Serialize with an actor or a serial queue so an older write can't land
   after a newer one.)
3. Longer term, replace the monolithic JSON with SQLite (raw `sqlite3` keeps
   the zero-dependency goal, or GRDB if a dependency is acceptable). That
   turns O(history) saves into O(1) row writes and makes "Forever" viable.

### 1.2 Image capture decodes and re-encodes on the main thread — multi-second UI freezes

The capture path runs inside the poll timer on the main actor:
`ClipboardMonitor.check()` → `ImageProcessor.makeItem` →
`NSImage(contentsOf:)` / `tiffRepresentation` → PNG encode → thumbnail render
(`ImageProcessor.swift:41-62`). For a 20 MB screenshot (the allowed max) this
is TIFF round-trip plus two PNG encodes — easily 1–3 seconds during which the
panel, the paste synthesizer, and every other app-side interaction freeze.
There's also a transient memory spike of roughly `width × height × 4 × 2`
bytes from the TIFF intermediate.

**Fixes**
- Grab `Data` from the pasteboard on the main actor (that part must stay
  there), then do decode/encode/thumbnail in `Task.detached` and hop back to
  the main actor for `store.insert(item)`.
- Skip the TIFF→PNG round trip when the pasteboard already offers PNG — store
  the original data and hash it directly.
- Use `CGImageSource`/`CGImageDestination` (ImageIO) for thumbnailing instead
  of `lockFocus()`; it's faster, lower-memory, and doesn't require the main
  thread.

### 1.3 Orphaned content files are never garbage-collected

Content files (`.rtf`, `.png`) are written to disk *before* the item is
inserted and *before* the debounced `store.json` save fires
(`ClipboardMonitor.swift:106`, `ImageProcessor.swift:74`). A crash or
force-quit in that 0.5 s window leaves files on disk that no item references
— forever. Nothing ever reconciles `content/` against `items`, so the
directory only grows, and `totalDataSize()` reports the orphans as "cached
data" the user cannot clear (Clear History only deletes referenced files).

**Fix**: on launch (background priority), list `contentDir` and delete any
file not referenced by `items[*].rtfFile/imageFile/thumbFile`. ~15 lines.

### 1.4 Paste synthesis races the target app's activation

`PasteService.paste()` (`PasteService.swift:66-78`) activates `previousApp`
and fires ⌘V after a fixed 0.25 s. If the target app is slow to become key
(heavy app, spaces transition, stage manager), the keystroke lands in the
wrong app — pasting clipboard contents into an unintended window is the worst
failure mode a clipboard manager can have. The multi-paste path stacks the
same bet at 0.35 s intervals (`AppState.pasteSequentially`,
`AppState.swift:126`).

**Fix**: wait for the activation instead of guessing — observe
`NSWorkspace.didActivateApplicationNotification` (already subscribed in this
class) for `previousApp`, then send ⌘V, with the current delay kept only as a
timeout fallback. For multi-paste, chain each ⌘V off the previous
confirmation rather than fixed sleeps.

### 1.5 Synchronous disk I/O inside SwiftUI `body`

Three spots do file-system work on the render path, re-executed on every
redraw (hover and selection animations redraw cards constantly):

- `SettingsView.swift:51` — `store.totalDataSize()` enumerates **every file
  in the content directory** each time the Settings form re-renders.
- `CardView.footerCenterLabel` (`CardView.swift:214-237`) —
  `FileManager.attributesOfItem` per card, per redraw, for file and image
  cards.
- `CardView.swift:144,159` and `PreviewPopover.swift:76` —
  `NSWorkspace.shared.icon(forFile:)` per row, per redraw (uncached, unlike
  `IconCache` which is only used for bundle IDs).

**Fixes**
- Store `byteSize: Int64?` on `ClipItem` at capture time — it never changes,
  and it removes the per-render `stat` calls entirely.
- Compute `totalDataSize()` once when the Settings window opens (`.task`
  modifier), show a placeholder meanwhile.
- Extend `IconCache` with a path-keyed variant for file icons.

### 1.6 `historyLimit` has two sources of truth

`Settings.historyLimit` and `Store.historyLimit` are separate stored values,
synced manually at launch (`AppDelegate.swift:22`) and in
`SettingsView.onChange` (`SettingsView.swift:59-61`). Any new mutation path
(a menu item, a CLI flag, iCloud-synced defaults) silently drifts the store's
copy. **Fix**: give `Store` a reference to `Settings` (or subscribe to its
publisher) and delete the duplicated property — the store should *read* the
limit, not own a copy.

---

## 2. Medium severity — robustness & design

### 2.1 Circular dependency wired with implicitly-unwrapped optionals

`AppState.pasteService: PasteService!` (`AppState.swift:16`) and the ten IUO
properties on `AppDelegate` (`AppDelegate.swift:5-13`) mean the object graph's
correctness is enforced only by initialization order in
`applicationDidFinishLaunching`. Reordering two lines produces a runtime
crash, not a compile error.

**Fixes**
- `AppState` only needs *paste/copy actions*, not the whole service. Inject a
  small protocol (`protocol PasteActions { func paste(_:plainText:); func copy(_:) }`)
  or closures at init, breaking the cycle and making `AppState` testable
  without AppKit.
- Extract a `Composition`/`AppContainer` struct that builds the full graph in
  its initializer with `let` properties, so the compiler proves the wiring.
  `AppDelegate` then holds one non-optional container.

### 2.2 `filteredItems` is recomputed O(n) at every touch point

`AppState.filteredItems` is a computed property called from `selectedItem`,
`moveSelection`, `ensureSelectionValid`, `paste(at:)`,
`orderedMultiSelection`, and the panel body — several times per keystroke,
each a fresh double `filter` pass over all items plus lowercasing every
item's text (`AppState.swift:31-45`). Invisible at 500 items; with "Forever"
histories (tens of thousands of items) every arrow key becomes an O(n) string
scan × the number of call sites.

**Fix**: make it a cached `@Published private(set) var filteredItems`,
recomputed only when `query`, `selectedTab`, or `store.items` change (the
Combine pipeline for this replaces the manual `objectWillChange` forwarding
in `AppState.init`). Precompute `lowercasedText` per item if search ever
feels slow.

### 2.3 The riskiest code has no test seams

The tested code (models, filtering, store, colors) is the code least likely
to break. `ClipboardMonitor.buildItem` — the highest-branching, most
regression-prone function in the app — is untestable because it takes a live
`NSPasteboard` and reaches into `NSWorkspace`. Same for `PasteService`.

**Fix**: introduce thin protocols for the seams:

```swift
protocol PasteboardReading {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func data(forType: NSPasteboard.PasteboardType) -> Data?
    func string(forType: NSPasteboard.PasteboardType) -> String?
    func fileURLs() -> [URL]
}
```

`NSPasteboard` conforms in an extension; tests use an in-memory fake. This
also lets `buildItem` become a pure function `(PasteboardReading, SourceApp?)
→ ClipItem?` that belongs in the core layer, not next to the timer.

### 2.4 Concurrency annotations aren't checked by the shipping build

The code is carefully annotated `@MainActor`, but the Makefile compiles with
`-swift-version 5` and no strict-concurrency flag, so none of it is enforced
— e.g. `HotKey` (not `@MainActor`) calls `handler` which touches
`PanelController` state, and the compiler would never flag a future mistake.
`Package.swift` declares tools 6.0 but pins `.v5` language mode.

**Fix**: add `-strict-concurrency=complete` to the Makefile now (cheap), and
migrate to Swift 6 language mode when the toolchain allows. The codebase is
small and already annotated; this is the cheapest time it will ever be.

### 2.5 File lists are newline-joined into `text`

Multi-file clips store paths as `paths.joined(separator: "\n")`
(`ClipboardMonitor.swift:71`) and every consumer re-splits on `\n`
(`PasteService.swift:47`, `CardView.swift:141,221`, `PreviewPopover.swift:74`).
Filenames can legally contain newlines, which silently corrupts the clip, and
the stringly-typed round trip is repeated in four places. **Fix**: add
`filePaths: [String]?` to `ClipItem` (keep decoding the old `text` form for
migration) and centralize access behind one computed property.

### 2.6 Dedup keeps stale metadata

`Store.insert` (`Store.swift:69-81`) moves an existing item to the front and
refreshes `createdAt`, but keeps the *old* `sourceAppBundleID/Name` — copy the
same string from a different app and the card still shows the original app's
color and icon, while the timestamp says "now". **Fix**: also copy
`sourceAppBundleID`, `sourceAppName` (and `kind`, in case link-detection now
classifies differently) from the new item.

### 2.7 Sensitive data hygiene

History (including anything copied from a terminal, e.g. tokens that aren't
marked `ConcealedType`) is stored as plaintext JSON and loose files with
default permissions. Cheap wins:

- `chmod 700` the `PasteClone` directory at creation.
- Write content files with `.completeFileProtection`-equivalent options where
  applicable, and pass `[.atomic]` (already done for the JSON, not for
  RTF/PNG writes — `ClipboardMonitor.swift:106`, `ImageProcessor.swift:74`).
- Consider a "skip transient copies larger than N MB" and an opt-in
  auto-expiry for history-only items.

### 2.8 Deprecated / legacy APIs

- `UTTypeConformsTo` + raw `"public.image"` string
  (`ImageProcessor.swift:16`): use `UniformTypeIdentifiers` —
  `url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)`.
- `Carbon` hotkey is a deliberate, documented trade-off (no permissions
  needed) — fine to keep, but isolate it behind a `HotKeyRegistering`
  protocol so a future `KeyboardShortcuts`-style implementation is a drop-in.

---

## 3. Structure & package layout

### 3.1 Proposed target split

Everything currently lives in one target, so the pure logic can't be built or
tested without AppKit, and the custom test harness must compile the entire
app. Split by dependency direction:

```
Sources/
  PasteoryCore/       Models, ContentHasher, color/link parsing, filtering,
                      Store, Settings model          (Foundation + CryptoKit only)
  PasteoryPlatform/   ClipboardMonitor, PasteService, ImageProcessor,
                      HotKey, caches                  (AppKit, depends on Core)
  PasteoryUI/         SwiftUI views, PanelController, SettingsWindow
                      (depends on Core + Platform)
  Pasteory/           main.swift + AppDelegate = composition root
```

Notes:
- `Models.swift`, `Store.swift`, `AppColors` (minus the `Color` extension),
  and the filter statics already have no AppKit dependency — this split is
  mostly file moves plus relocating `Color(hex:)` into the UI layer.
- `AppState` belongs in Core once the `PasteService` reference becomes a
  protocol (§2.1) — it's the app's most valuable logic and currently imports
  AppKit only for that one property.
- Tests then target `PasteoryCore` alone: faster builds, no `@MainActor`
  gymnastics in the harness, and room to test `buildItem` via the pasteboard
  protocol (§2.3).

### 3.2 Makefile vs Package.swift drift

The Makefile is the real build (documented as a workaround for a broken local
SwiftPM) and `Package.swift` is aspirational. They already disagree: the
manifest builds three targets with module boundaries; the Makefile globs all
sources into one module, which is why `main.swift` needs the
`#if canImport(PasteCloneKit)` shim. Risks: code that compiles in one build
and not the other (access levels, module-qualified names).

**Fixes**
- Treat SwiftPM as the source of truth and make the Makefile a thin wrapper
  (`swift build`) with the direct-`swiftc` path kept as a documented fallback
  target (`make bundle-noswiftpm`).
- Add CI (GitHub Actions `macos-14` runner has a healthy toolchain) that runs
  `swift build && swift test` so the manifest can't silently rot, and migrate
  the custom harness to `swift-testing`/XCTest there while keeping the local
  runner for the broken-CLT machine.

### 3.3 Naming drift

Four names coexist: repo `pasteory`, product `Clap`, module `PasteClone`,
data dir `PasteClone`. The README acknowledges this, but user-facing strings
are also inconsistent in code — `HotKey` signature `'PCLN'`, log prefix
`PasteClone:`, accessibility description `"Clap"`. Centralize in one
namespace (`enum AppInfo { static let name = "Clap"; static let dataDirectory = "PasteClone"; … }`)
so a future rename is one file.

### 3.4 Duplication worth folding

- Byte formatting exists twice with different behavior
  (`CardView.formatSize`, `SettingsView.formatDataSize`). Replace both with
  one shared helper or `ByteCountFormatter`.
- The luminance-threshold text-color rule (`> 0.6 ? .black : .white`) is
  duplicated in `CardView` (twice) and `PreviewPopover`; make it
  `ParsedColor.readableTextColor` / `AppColors.readableTextColor(onHex:)`.
- `relativeTimeString` caps at days ("365d"); consider weeks after 14 d —
  cosmetic.

### 3.5 Magic numbers → one constants surface

Timing and layout constants that interact are scattered: panel height 360,
show/hide animation 0.22/0.18 s, paste delay 0.25 s (must exceed the hide
animation — this coupling is only documented in a comment), multi-paste
interval 0.35 s, poll interval 0.5 s, save debounce 0.5 s, card size 240×280.
Group them in a `Tuning` enum so the relationships are visible and adjustable
in one place.

---

## 4. Smaller observations

| Where | Issue | Suggestion |
|---|---|---|
| `Store.swift:38-41` | Second corruption overwrites the previous `.corrupt` backup | Timestamp the backup filename |
| `Store.swift:107` | Pinboard color assigned by `pinboards.count` — deleting then adding reuses colors non-uniquely | Pick first palette color not in use |
| `ClipboardMonitor.swift:80` | `pb.data(forType: .png) ?? .tiff` misses images offered only as `.pdf` or file-promise | Acceptable scope cut; document it |
| `Models.swift:95` | `looksLikeCode` fires on any `{` or `;` — prose with a semicolon renders monospaced | Require ≥2 signals or a newline |
| `PasteService.swift:34` | `copy(_:plainText:)`'s `plainText` is ignored for `.image`/`.file` (fine) but also not plumbed through the ⌘C path | Intentional? If so, drop the param from `copy` and strip in `paste` only |
| `PreviewPopover.swift:54` | Full-size image decoded via `NSImage(contentsOf:)` on every body evaluation | Route through `ImageCache` |
| `PanelController.swift:29` | Initial `contentRect` width 1200 is dead — immediately replaced by screen frame | Use a nominal 1×1 or comment |
| `AppDelegate.swift:64` | Accessibility description says "Clap" but menu-item comments/log lines mix names | Covered by §3.3 |
| `Settings.swift:43` | `panelOpacity == 0` sentinel means a user genuinely wanting 0 can't (range floor is 0.3, so harmless today) | Use `object(forKey:) == nil` to detect "never set" |
| `Info.plist` | No `NSSupportsAutomaticTermination`/`LSApplicationCategoryType`; version hardcoded 1.0 | Stamp version from git in `make bundle` |

---

## 5. Suggested order of work

1. **Data safety** (§1.1, §1.3): schema version + logged, background saves;
   startup orphan GC. Small diffs, biggest downside protection.
2. **Main-thread I/O** (§1.2, §1.5): background image processing; stored
   `byteSize`; cached file icons; async settings size.
3. **Paste reliability** (§1.4): activation-confirmed ⌘V.
4. **Seams & wiring** (§2.1, §2.3, §1.6): protocols for pasteboard + paste
   actions, composition root, single `historyLimit` owner. This unlocks tests
   for `buildItem`.
5. **Build health** (§2.4, §3.2): strict concurrency flag, CI running SwiftPM.
6. **Structure** (§3.1): target split — do last; it's mechanical once the
   seams from step 4 exist.
