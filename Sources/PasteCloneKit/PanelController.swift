import AppKit
import SwiftUI

/// Non-activating panels never become key by default; we need keyboard input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class PanelController {
    public static let panelHeight: CGFloat = 360

    private let panel: KeyablePanel
    private let appState: AppState
    private let pasteService: PasteService

    public private(set) var isVisible = false
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var outsideClickMonitor: Any?
    private var scrollMonitor: Any?

    public init(appState: AppState, pasteService: PasteService) {
        self.appState = appState
        self.pasteService = pasteService

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: Self.panelHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true

        let root = PanelRootView()
            .environmentObject(appState)
            .environment(appState.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        pasteService.willPaste = { [weak self] in self?.hidePanel() }
    }

    public func toggle() {
        isVisible ? hidePanel() : showPanel()
    }

    public func showPanel() {
        guard !isVisible else { return }
        let screen = screenWithMouse() ?? NSScreen.main
        guard let screen else { return }

        pasteService.previousApp = NSWorkspace.shared.frontmostApplication
        appState.panelDidShow()

        let target = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: Self.panelHeight
        )
        var start = target
        start.origin.y -= Self.panelHeight

        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()

        // Becoming key hands first-responder to the panel's only focusable
        // view — the search field — which puts the panel in search mode
        // (arrows edit text, Esc clears the query) before the user asked
        // for it. Start in browse mode; typing any character re-focuses the
        // field via appendToQuery. SwiftUI assigns focus on the next runloop
        // turn, so the reset has to be scheduled one tick out.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.panel.makeFirstResponder(nil)
            self.appState.searchFocused = false
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }

        installMonitors()
        isVisible = true
    }

    public func hidePanel() {
        guard isVisible else { return }
        isVisible = false
        removeMonitors()
        appState.previewItem = nil
        appState.showNumbers = false
        // Flush any debounced writes now rather than risk losing the last
        // mutation if the app is force-quit before the 0.5s save timer fires.
        appState.store.saveNow()

        var down = panel.frame
        down.origin.y -= Self.panelHeight
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(down, display: true)
        }, completionHandler: { [weak panel] in
            Task { @MainActor in panel?.orderOut(nil) }
        })
    }

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Event monitors

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.appState.showNumbers = event.modifierFlags.contains(.command)
            return event
        }
        // Global monitor only fires for OTHER apps' clicks — i.e. outside the panel.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        // SwiftUI's ScrollView(.horizontal) only responds to trackpad
        // horizontal swipes, not a plain mouse wheel — but Paste's own
        // timeline does. Rather than replace the scroll view (which broke
        // keyboard-driven scroll-to-selection), swap the wheel event's axes
        // and let the same, already-working ScrollView handle it.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Only the card row scrolls sideways — leave the Quick Look
            // preview's vertical text scroller and other windows (Settings)
            // alone.
            guard let self, event.window === self.panel,
                  self.appState.previewItem == nil
            else { return event }
            return horizontalizedWheelEvent(event) ?? event
        }
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, flagsMonitor, outsideClickMonitor, scrollMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        flagsMonitor = nil
        outsideClickMonitor = nil
        scrollMonitor = nil
    }

    /// Returns nil to consume the event.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // The key monitor is local to this app and fires for every keyDown
        // regardless of which of the app's windows is actually focused. If
        // Settings is open and key (e.g. while editing the excluded-apps
        // list) while the panel is merely visible behind it, don't steal
        // its keystrokes.
        guard panel.isKeyWindow else { return event }

        let state = appState
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCmd = mods.contains(.command)

        // ⌘1–⌘9 quick paste (base character, so ⇧⌘1 doesn't read as "!"
        // and still pastes as plain text)
        if hasCmd, let chars = event.characters(byApplyingModifiers: []),
           let n = Int(chars), (1...9).contains(n) {
            state.paste(at: n - 1, plainText: mods.contains(.shift))
            return nil
        }
        // ⇧⌘N new pinboard
        if hasCmd, mods.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "n" {
            createPinboardInteractively(state: state)
            return nil
        }
        // ⌘F focus search
        if hasCmd, event.charactersIgnoringModifiers == "f" {
            state.searchFocused = true
            return nil
        }
        // ⌘C copy selected (only while browsing cards)
        if hasCmd, event.charactersIgnoringModifiers == "c", !state.searchFocused {
            state.copySelected()
            hidePanel()
            return nil
        }
        // ⌘R rename selected item
        if hasCmd, event.charactersIgnoringModifiers == "r", !state.searchFocused {
            if let item = state.selectedItem,
               let name = promptForText(title: "Rename Item", message: "Title:",
                                        defaultValue: item.title ?? "") {
                state.store.renameItem(item.id, title: name)
            }
            return nil
        }

        switch event.keyCode {
        case 53: // Esc
            if state.previewItem != nil {
                state.previewItem = nil
            } else if state.searchFocused || !state.query.isEmpty {
                state.query = ""
                state.searchFocused = false
                state.ensureSelectionValid()
            } else {
                hidePanel()
            }
            return nil
        case 36: // Return
            if !state.multiSelection.isEmpty {
                state.pasteMultiSelection(plainText: mods.contains(.shift))
            } else {
                state.pasteSelected(plainText: mods.contains(.shift))
            }
            return nil
        case 123: // ←
            // Arrows always drive the cards, even mid-search: leave the
            // field (keeping the query filter) and move on the results.
            state.searchFocused = false
            state.moveSelection(by: -1)
            return nil
        case 124: // →
            state.searchFocused = false
            state.moveSelection(by: 1)
            return nil
        case 49: // Space
            if !state.searchFocused {
                state.previewItem = state.previewItem == nil ? state.selectedItem : nil
                return nil
            }
            return event
        case 51: // Delete (backspace)
            if !state.searchFocused { state.deleteSelected(); return nil }
            return event
        case 48: // Tab
            state.searchFocused.toggle()
            return nil
        default:
            break
        }

        // Type-to-search: printable characters while browsing cards.
        if !state.searchFocused, !hasCmd, !mods.contains(.control),
           let chars = event.characters,
           !chars.isEmpty,
           chars.rangeOfCharacter(from: .alphanumerics.union(.punctuationCharacters).union(.symbols)) != nil {
            state.appendToQuery(chars)
            moveSearchCaretToEndAfterFocus()
            return nil
        }

        return event
    }

    /// Focusing the search field programmatically (as opposed to a mouse
    /// click) makes AppKit select all of its existing text. Without this, a
    /// second fast keystroke right after the first would overwrite it
    /// instead of appending — since the field editor doesn't take over focus
    /// until the next runloop turn, this is scheduled one tick out.
    private func moveSearchCaretToEndAfterFocus() {
        DispatchQueue.main.async { [weak panel] in
            guard let editor = panel?.firstResponder as? NSTextView else { return }
            let end = editor.string.count
            editor.setSelectedRange(NSRange(location: end, length: 0))
        }
    }
}

/// Swaps a scroll-wheel event's vertical/horizontal deltas so a plain mouse
/// wheel drives horizontal scrolling. Trackpad swipes already carry a
/// meaningful horizontal delta and are passed through untouched. Returns nil
/// when the event can't be transformed (e.g. no backing CGEvent), in which
/// case the caller falls back to the original event.
private func horizontalizedWheelEvent(_ event: NSEvent) -> NSEvent? {
    guard abs(event.scrollingDeltaX) < 0.01, abs(event.scrollingDeltaY) > 0.01,
          let cgEvent = event.cgEvent?.copy()
    else { return nil }

    let vertical = cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
    let verticalPoint = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
    cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
    cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
    cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: vertical)
    cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: verticalPoint)

    return NSEvent(cgEvent: cgEvent)
}
