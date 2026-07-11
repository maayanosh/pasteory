import Foundation

/// The slice of paste behavior AppState and the views depend on. Injecting
/// this instead of the concrete PasteService breaks the construction-order
/// coupling and lets tests drive AppState without touching the real
/// pasteboard or the Accessibility APIs.
@MainActor
public protocol PasteActions: AnyObject {
    /// Copies the item, refocuses the previous app, and synthesizes ⌘V once
    /// that app is frontmost. `completion` fires after the keystroke has had
    /// time to land — used to chain multi-item pastes safely.
    func paste(_ item: ClipItem, plainText: Bool, completion: (() -> Void)?)
    /// Copies the item to the system pasteboard without pasting.
    func copy(_ item: ClipItem)
}

public extension PasteActions {
    func paste(_ item: ClipItem) {
        paste(item, plainText: false, completion: nil)
    }

    func paste(_ item: ClipItem, plainText: Bool) {
        paste(item, plainText: plainText, completion: nil)
    }
}
