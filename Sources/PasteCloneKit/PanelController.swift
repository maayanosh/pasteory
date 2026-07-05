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

        let root = PanelRootView().environmentObject(appState)
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
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, flagsMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        flagsMonitor = nil
        outsideClickMonitor = nil
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

        // ⌘1–⌘9 quick paste
        if hasCmd, let chars = event.charactersIgnoringModifiers,
           let n = Int(chars), (1...9).contains(n) {
            state.paste(at: n - 1, plainText: mods.contains(.shift))
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
            if !state.searchFocused { state.moveSelection(by: -1); return nil }
            return event
        case 124: // →
            if !state.searchFocused { state.moveSelection(by: 1); return nil }
            return event
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
