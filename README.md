# Clap

A native macOS clipboard manager inspired by [Paste](https://pasteapp.io) — a
bottom slide-up panel, color-coded history cards, pinboards, search, and
quick-paste shortcuts. Built with Swift + SwiftUI + AppKit. No Xcode project,
no third-party dependencies, no accounts, no sync — everything stays local on
your Mac.

## Features

- **Global hotkey** (**⇧⌘V**) slides a translucent panel up from the
  bottom of the screen without stealing focus from the app you were using.
- **Horizontal card timeline** of clipboard history — text, rich text,
  images, links, and file references — each card color-coded by source app.
- **Type-to-search** — just start typing while the panel is open to filter
  cards in real time (⌘F to focus search explicitly).
- **Pinboards** (⇧⌘N) — organize items into named boards that persist
  outside of history.
- **Quick paste** — hold ⌘ to overlay numbers 1–9 on the first cards; ⌘1–⌘9
  pastes instantly.
- **Quick Look** — press Space on a selected card for a large preview.
- **Privacy-aware** — ignores concealed/password clipboard content
  (`org.nspasteboard.ConcealedType`), with a pause-capture toggle.
- **Dedup** — re-copying an existing item moves it to the front instead of
  creating a duplicate.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon or Intel.
- Xcode Command Line Tools (for `swiftc`). A full Xcode install is not
  required.

## Installation

Clone the repo and build the app bundle with `make`:

```sh
git clone https://github.com/maayanosh/pasteory.git
cd pasteory
make open
```

`make open` builds `build/Clap.app`, ad-hoc code-signs it, and opens it.
Other useful targets:

| Command       | What it does                                      |
|---------------|----------------------------------------------------|
| `make bundle` | Build the signed `.app` bundle without launching it |
| `make run`    | Build and run the binary directly (no Dock/menu bar bundle context) |
| `make test`   | Build and run the unit test suite                 |
| `make clean`  | Remove build artifacts                            |

> **Why `make` and not `swift build`?** The project ships a `Package.swift`
> for editing in Xcode/SwiftPM-aware editors, but the Makefile drives `swiftc`
> directly so the build doesn't depend on SwiftPM's manifest tooling working
> correctly on every machine. If your toolchain is healthy, `swift build` /
> opening the folder in Xcode should also work.

### Grant Accessibility permission

Pasting into the previously active app is done by simulating ⌘V, which
requires the Accessibility permission:

1. Run `make open` once — Clap will prompt you.
2. Go to **System Settings → Privacy & Security → Accessibility** and enable
   **Clap**.
3. Re-open the app if it doesn't pick up the permission immediately.

Note: because the app is ad-hoc signed, you'll need to re-grant this
permission after rebuilding from source.

Without this permission, pressing Return on a card copies the item to your
clipboard instead of pasting it in place.

### Data storage

Clipboard history and pinboards are stored locally at
`~/Library/Application Support/PasteClone/`. Nothing leaves your Mac.

## Usage

| Shortcut | Action |
|---|---|
| ⇧⌘V | Open/close the panel |
| Type anything | Filter history by search |
| ← / → | Move selection |
| Return | Paste selected item into the previous app |
| ⇧ + Return | Paste as plain text (strips formatting) |
| ⌘C | Copy selected item back to the clipboard without pasting |
| ⌘1–⌘9 (hold ⌘) | Quick-paste one of the first 9 items |
| ⌘-click | Add cards to a multi-selection; Return pastes them all in order |
| ⌘R | Rename the selected item (also in the right-click menu) |
| Space | Quick Look preview of the selected item |
| ⇧⌘N | Create a new pinboard |
| Delete | Remove the selected item |
| Esc | Close the panel |

## Development

Project layout:

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

`ClapCore` imports only Foundation and Observation; it defines the `Paster`, `ClipboardSource`, `GlobalHotKey`, and `LaunchAtLoginController` seams that a future non-macOS front-end would implement.

The code predates the Clap name, so internal identifiers (module names, the
`com.local.pasteclone` bundle id, the `PasteClone` data directory) keep the
original naming.

Run the test suite with:

```sh
make test
```

Setting `PASTECLONE_SHOW_ON_LAUNCH=1` makes the app auto-open the panel
shortly after launch, which is useful for scripted/automated verification.

## Contributing

Issues and pull requests are welcome. Please keep changes scoped and include
tests where practical (`make test` should stay green).

## License

MIT — see [LICENSE](LICENSE).

Clap is an independent, unaffiliated project inspired by the design of
[Paste](https://pasteapp.io). It is not endorsed by or affiliated with
Paste/Wivpro Corp.
