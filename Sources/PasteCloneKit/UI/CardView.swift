import SwiftUI

struct CardView: View {
    @Environment(AppState.self) private var state
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
            case .text, .richText, .link, .color:
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
        case .color: "paintpalette"
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
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .file:
                let paths = (item.text ?? "").split(separator: "\n").map(String.init)
                if paths.count == 1 {
                    VStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: paths[0]))
                            .resizable()
                            .frame(width: 48, height: 48)
                        Text(URL(fileURLWithPath: paths[0]).lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(paths, id: \.self) { path in
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .color:
                let parsed = parseColorString(item.text ?? "")
                    ?? ParsedColor(red: 0, green: 0, blue: 0)
                ZStack {
                    Color(red: parsed.red, green: parsed.green, blue: parsed.blue)
                        .opacity(parsed.alpha)
                    Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(parsed.luminance > 0.6 ? Color.black : .white)
                        .lineLimit(2)
                        .padding(8)
                }
            }
        }
    }

    private var footer: some View {
        ZStack {
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
            if let label = footerCenterLabel {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var footerCenterLabel: String? {
        switch item.kind {
        case .text, .richText:
            guard let text = item.text else { return nil }
            let byteSize = formatSize(Int64(Data(text.utf8).count))
            return "\(text.count) chars · \(byteSize)"
        case .file:
            let paths = (item.text ?? "").split(separator: "\n").map(String.init)
            let total = paths.reduce(Int64(0)) { acc, path in
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                return acc + size
            }
            return total > 0 ? formatSize(total) : nil
        case .image:
            if let file = item.imageFile {
                let url = state.store.contentURL(file)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                return size > 0 ? formatSize(size) : nil
            }
            return nil
        case .link, .color:
            return nil
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) bytes"
        }
        return value < 10
            ? String(format: "%.1f %@", value, units[unitIndex])
            : String(format: "%.0f %@", value, units[unitIndex])
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Paste") { state.selection.paste(item) }
        Button("Paste as Plain Text") { state.selection.paste(item, plainText: true) }
        Button("Copy") { state.selection.copy(item) }
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
