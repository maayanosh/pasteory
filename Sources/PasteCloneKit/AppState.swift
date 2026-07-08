import AppKit
#if canImport(ClapCore)
import ClapCore
#endif

/// macOS-side glue: owns the core SelectionState + Store + Settings.
/// Views read `state.selection`, `state.store`, `state.settings`.
@Observable
@MainActor
public final class AppState {
    // `var` (not `let`) so `$state.selection.query`'s composed keypath is a
    // ReferenceWritableKeyPath, letting SwiftUI's @Bindable bind through the
    // nested SelectionState. Never reassigned after init.
    public var selection: SelectionState
    public let settings: Settings
    public var store: Store { selection.store }

    public init(store: Store, settings: Settings, paster: Paster) {
        self.selection = SelectionState(store: store)
        self.settings = settings
        self.selection.paster = paster
    }
}
