import SwiftUI

struct CardView: View {
    @EnvironmentObject var state: AppState
    let item: ClipItem
    let isSelected: Bool
    let quickPasteNumber: Int?

    @State private var hovering = false

    private var headerHex: String { AppColors.hex(for: item.sourceAppBundleID) }
    private var headerTextColor: Color {
        AppColors.luminance(ofHex: headerHex) > 0.6 ? .black : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            titleRow
            body_
            footer
        }
        .frame(width: 240, height: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 3 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if let n = quickPasteNumber {
                Text("⌘\(n)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 22)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .scaleEffect(isSelected ? 1.02 : (hovering ? 1.01 : 1.0))
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
        .onDrag {
            switch item.kind {
            case .text, .richText, .link:
                return NSItemProvider(object: (item.text ?? "") as NSString)
            case .file:
                let path = (item.text ?? "").split(separator: "\n").first.map(String.init) ?? ""
                return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
            case .image:
                if let file = item.imageFile,
                   let image = NSImage(contentsOf: state.store.contentURL(file)) {
                    return NSItemProvider(object: image)
                }
                return NSItemProvider()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(item.sourceAppName ?? "Unknown")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Image(systemName: kindSymbol)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(headerTextColor)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(Color(hex: headerHex))
    }

    private var kindSymbol: String {
        switch item.kind {
        case .text, .richText: "doc.text"
        case .image: "photo"
        case .link: "link"
        case .file: "doc"
        }
    }

    @ViewBuilder
    private var titleRow: some View {
        if let title = item.title, !title.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var body_: some View {
        Group {
            switch item.kind {
            case .text, .richText:
                Text(item.text ?? "")
                    .font(looksLikeCode(item.text ?? "")
                          ? .system(size: 11, design: .monospaced)
                          : .system(size: 12))
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            case .link:
                VStack(alignment: .leading, spacing: 6) {
                    Text(URL(string: item.text ?? "")?.host ?? "link")
                        .font(.system(size: 14, weight: .bold))
                    Text(item.text ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            case .image:
                if let file = item.thumbFile ?? item.imageFile,
                   let nsImage = ImageCache.shared.image(at: state.store.contentURL(file)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 240, height: 214)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .file:
                VStack(spacing: 8) {
                    let firstPath = (item.text ?? "").split(separator: "\n").first.map(String.init) ?? ""
                    Image(nsImage: NSWorkspace.shared.icon(forFile: firstPath))
                        .resizable()
                        .frame(width: 48, height: 48)
                    Text(URL(fileURLWithPath: firstPath).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(forBundleID: item.sourceAppBundleID))
            Text(relativeTimeString(from: item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            if item.pinboardID != nil {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Paste") { state.pasteService.paste(item) }
        Button("Paste as Plain Text") { state.pasteService.paste(item, plainText: true) }
        Button("Copy") { state.pasteService.copy(item) }
        Divider()
        Button("Rename…") {
            if let name = promptForText(title: "Rename Item",
                                        message: "Title:",
                                        defaultValue: item.title ?? "") {
                state.store.renameItem(item.id, title: name)
            }
        }
        Divider()
        if item.pinboardID == nil {
            Menu("Pin to") {
                ForEach(state.store.pinboards) { board in
                    Button(board.name) { state.store.setPinboard(item.id, to: board.id) }
                }
                if state.store.pinboards.isEmpty {
                    Button("New Pinboard…") {
                        let board = state.store.addPinboard(name: "Pinboard 1")
                        state.store.setPinboard(item.id, to: board.id)
                    }
                }
            }
        } else {
            Button("Unpin") { state.store.setPinboard(item.id, to: nil) }
        }
        Divider()
        Button("Delete", role: .destructive) { state.store.delete(item.id) }
    }
}
