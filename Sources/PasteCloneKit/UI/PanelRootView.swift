import SwiftUI

public struct PanelRootView: View {
    @Environment(AppState.self) private var state
    @Environment(Settings.self) private var settings

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                cardRow
            }
            if let item = state.previewItem {
                PreviewPopover(item: item)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(settings.panelOpacity))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: state.previewItem)
        .environment(\.colorScheme, .dark) // Paste's panel reads dark over any wallpaper
    }

    private var header: some View {
        HStack(spacing: 12) {
            PinboardTabs()
            Spacer()
            SearchBar()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var cardRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    let items = state.filteredItems
                    if items.isEmpty {
                        emptyState
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        CardView(
                            item: item,
                            isSelected: item.id == state.selectionID || state.multiSelection.contains(item.id),
                            quickPasteNumber: state.showNumbers && index < 9 ? index + 1 : nil
                        )
                        .id(item.id)
                        .onTapGesture(count: 2) { state.pasteService.paste(item) }
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                state.toggleMultiSelect(item.id)
                                state.selectionID = item.id
                            } else {
                                state.clearMultiSelection()
                                state.selectionID = item.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 4)
            }
            .onChange(of: state.selectionID) { _, id in
                if let id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(state.query.isEmpty ? "Nothing here yet — copy something!" : "No results")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if state.query.isEmpty {
                Text("Open this panel anytime with ⇧⌘V")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 400, height: 280)
    }
}
