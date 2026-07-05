import SwiftUI

struct PinboardTabs: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            tab(title: "History", color: nil, id: nil)
            ForEach(state.store.pinboards) { board in
                tab(title: board.name, color: Color(hex: board.colorHex), id: board.id)
                    .contextMenu {
                        Button("Rename…") { rename(board) }
                        Button("Delete Pinboard", role: .destructive) {
                            if state.selectedTab == board.id { state.selectedTab = nil }
                            state.store.deletePinboard(board.id)
                        }
                    }
            }
            Button {
                createPinboard()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .help("New Pinboard (⇧⌘N)")
        }
    }

    private func tab(title: String, color: Color?, id: UUID?) -> some View {
        let selected = state.selectedTab == id
        return Button {
            state.selectedTab = id
            state.ensureSelectionValid()
        } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
        }
        .buttonStyle(.plain)
        .background(
            selected ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 7)
        )
    }

    private func createPinboard() {
        if let name = promptForText(title: "New Pinboard",
                                    message: "Name your pinboard:",
                                    defaultValue: "Pinboard \(state.store.pinboards.count + 1)") {
            let board = state.store.addPinboard(name: name)
            state.selectedTab = board.id
        }
    }

    private func rename(_ board: Pinboard) {
        if let name = promptForText(title: "Rename Pinboard",
                                    message: "New name:",
                                    defaultValue: board.name) {
            state.store.renamePinboard(board.id, to: name)
        }
    }
}

@MainActor
func promptForText(title: String, message: String, defaultValue: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    field.stringValue = defaultValue
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let value = field.stringValue.trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? nil : value
}
