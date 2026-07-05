import AppKit

@MainActor
public final class PasteService {
    private let store: Store
    private let monitor: ClipboardMonitor
    /// The app that was frontmost before the panel opened; set by PanelController.
    public var previousApp: NSRunningApplication?
    /// Called before synthesizing ⌘V so the panel can dismiss itself.
    public var willPaste: (() -> Void)?

    private var promptedForAccessibility = false

    public init(store: Store, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    /// Copy the item to the system pasteboard without pasting.
    public func copy(_ item: ClipItem, plainText: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .image:
            if let file = item.imageFile,
               let data = try? Data(contentsOf: store.contentURL(file)),
               let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        case .file:
            let urls = (item.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            pb.writeObjects(urls)
        case .richText:
            if !plainText,
               let file = item.rtfFile,
               let rtf = try? Data(contentsOf: store.contentURL(file)) {
                pb.setData(rtf, forType: .rtf)
            }
            pb.setString(item.text ?? "", forType: .string)
        case .text, .link:
            pb.setString(item.text ?? "", forType: .string)
        }

        // Prevent the monitor from recapturing (and reordering) this item.
        monitor.expectedChangeCount = pb.changeCount
    }

    /// Copy the item, restore focus to the previous app, and synthesize ⌘V.
    public func paste(_ item: ClipItem, plainText: Bool = false) {
        willPaste?()
        copy(item, plainText: plainText)
        previousApp?.activate()

        guard ensureAccessibility() else { return } // degraded: copy-only

        // Give the target app time to become key before the keystroke lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.sendCmdV()
        }
    }

    private func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !promptedForAccessibility {
            promptedForAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        return false
    }

    static func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
