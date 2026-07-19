import AppKit

@MainActor
public final class PasteService: PasteActions {
    private let store: Store
    private let monitor: ClipboardMonitor
    /// The last non-Clap app that was frontmost. Updated automatically via
    /// Workspace notifications so it stays correct even when the Carbon hotkey
    /// briefly activates this process before showPanel() runs.
    public var previousApp: NSRunningApplication?
    /// Called before synthesizing ⌘V so the panel can dismiss itself.
    public var willPaste: (() -> Void)?

    private var promptedForAccessibility = false
    private var workspaceObserver: NSObjectProtocol?
    private var pendingActivation: (observer: NSObjectProtocol, timeout: DispatchWorkItem)?

    /// The panel's hide animation (0.18s) must release key status before the
    /// synthesized keystroke lands, so ⌘V never fires earlier than this after
    /// paste() is called.
    private static let panelHideGrace: TimeInterval = 0.25
    /// Settle time between the target app reporting activation and ⌘V, so its
    /// key window can take focus.
    private static let keystrokeDelay: TimeInterval = 0.05
    /// If the target app never reports activation, send ⌘V anyway after this.
    private static let activationTimeout: TimeInterval = 0.5
    /// How long a synthesized ⌘V gets to be consumed by the target app before
    /// a chained multi-paste overwrites the pasteboard with the next item.
    private static let interPasteDelay: TimeInterval = 0.1

    public init(store: Store, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self?.previousApp = app
        }
    }

    /// Copy the item to the system pasteboard without pasting.
    public func copy(_ item: ClipItem) {
        write(item, plainText: false)
    }

    private func write(_ item: ClipItem, plainText: Bool) {
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
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        case .richText:
            if !plainText,
               let file = item.rtfFile,
               let rtf = try? Data(contentsOf: store.contentURL(file)) {
                pb.setData(rtf, forType: .rtf)
            }
            pb.setString(item.text ?? "", forType: .string)
        case .text, .link, .color:
            pb.setString(item.text ?? "", forType: .string)
        }

        // Prevent the monitor from recapturing (and reordering) this item.
        monitor.expectedChangeCount = pb.changeCount
    }

    /// Copy the item, restore focus to the previous app, and synthesize ⌘V
    /// once that app is actually frontmost — a fixed delay alone can land the
    /// keystroke in the wrong app when activation is slow.
    public func paste(_ item: ClipItem, plainText: Bool = false, completion: (() -> Void)? = nil) {
        willPaste?()
        write(item, plainText: plainText)

        let floor = DispatchTime.now() + Self.panelHideGrace
        let target = previousApp
        target?.activate()

        guard ensureAccessibility() else { return } // degraded: copy-only

        if let target, !target.isActive {
            sendCmdVAfterActivation(of: target, notBefore: floor, completion: completion)
        } else {
            // Common case: the non-activating panel never stole frontmost
            // status, so only the hide animation needs to finish.
            scheduleCmdV(notBefore: floor, completion: completion)
        }
    }

    // MARK: - Keystroke scheduling

    private func scheduleCmdV(notBefore floor: DispatchTime, completion: (() -> Void)?) {
        cancelPendingActivation()
        let fireAt = max(floor, DispatchTime.now() + Self.keystrokeDelay)
        DispatchQueue.main.asyncAfter(deadline: fireAt) {
            Self.sendCmdV()
            if let completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.interPasteDelay) {
                    completion()
                }
            }
        }
    }

    private func sendCmdVAfterActivation(of target: NSRunningApplication,
                                         notBefore floor: DispatchTime,
                                         completion: (() -> Void)?) {
        cancelPendingActivation()

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingActivation != nil else { return }
            self.scheduleCmdV(notBefore: floor, completion: completion)
        }
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.pendingActivation != nil,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == target.processIdentifier
            else { return }
            self.scheduleCmdV(notBefore: floor, completion: completion)
        }
        pendingActivation = (observer, timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationTimeout, execute: timeout)
    }

    private func cancelPendingActivation() {
        guard let pending = pendingActivation else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(pending.observer)
        pending.timeout.cancel()
        pendingActivation = nil
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
