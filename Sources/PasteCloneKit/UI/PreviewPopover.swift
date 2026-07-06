import SwiftUI

/// Quick Look-style large preview shown over the card row (Space toggles).
struct PreviewPopover: View {
    @EnvironmentObject var state: AppState
    let item: ClipItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture { state.previewItem = nil }
            content
                .frame(maxWidth: 700, maxHeight: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(radius: 24)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text, .richText:
            ScrollView {
                Text(item.text ?? "")
                    .font(looksLikeCode(item.text ?? "")
                          ? .system(size: 12, design: .monospaced)
                          : .system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
            }
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                Text(URL(string: item.text ?? "")?.host ?? "Link")
                    .font(.system(size: 18, weight: .bold))
                Text(item.text ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Open in Browser") {
                    if let url = URL(string: item.text ?? "") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        case .image:
            if let file = item.imageFile,
               let nsImage = NSImage(contentsOf: state.store.contentURL(file)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            }
        case .color:
            let parsed = parseColorString(item.text ?? "")
                ?? ParsedColor(red: 0, green: 0, blue: 0)
            ZStack {
                Color(red: parsed.red, green: parsed.green, blue: parsed.blue)
                    .opacity(parsed.alpha)
                Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(parsed.luminance > 0.6 ? Color.black : .white)
                    .textSelection(.enabled)
            }
            .frame(width: 460, height: 280)
        case .file:
            VStack(spacing: 10) {
                ForEach((item.text ?? "").split(separator: "\n").prefix(6), id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: String(path)))
                            .resizable().frame(width: 24, height: 24)
                        Text(String(path))
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(24)
        }
    }
}
