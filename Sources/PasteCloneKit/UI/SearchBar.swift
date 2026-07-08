import SwiftUI

struct SearchBar: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var state = state
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search", text: $state.selection.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onChange(of: state.selection.query) { _, _ in
                    state.selection.ensureSelectionValid()
                }
            if !state.selection.query.isEmpty {
                Button {
                    state.selection.query = ""
                    state.selection.searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: focused || !state.selection.query.isEmpty ? 280 : 220, height: 30)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? Color.accentColor.opacity(0.6) : .white.opacity(0.08),
                        lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        // Two-way sync between SwiftUI focus and the AppState flag the
        // keyboard handler in PanelController relies on.
        .onChange(of: focused) { _, now in
            if state.selection.searchFocused != now { state.selection.searchFocused = now }
        }
        .onChange(of: state.selection.searchFocused) { _, now in
            if focused != now { focused = now }
        }
    }
}
