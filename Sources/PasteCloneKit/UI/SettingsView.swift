import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: Store
    @State private var dataSize: Int64?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Pause clipboard capture", isOn: $settings.isPaused)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Auto-paste on Enter", isOn: $settings.pasteOnEnter)
                Picker("Keep history", selection: $settings.historyLimit) {
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("1000 items").tag(1000)
                    Text("Forever").tag(Int.max)
                }
                HStack {
                    Text("Panel opacity")
                    Slider(value: $settings.panelOpacity, in: 0.3...1.0)
                    Text("\(Int((settings.panelOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                LabeledContent("Open Clap", value: "⇧⌘V")
            }
            Section("Privacy — Excluded Apps") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("Copies from excluded apps are never saved.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { bid in
                    HStack {
                        Image(nsImage: IconCache.shared.icon(forBundleID: bid))
                        Text(bid)
                        Spacer()
                        Button {
                            settings.excludedBundleIDs.removeAll { $0 == bid }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add App…") { addApp() }
            }
            Section("Data") {
                // Computed off the main thread on appearance — walking the
                // whole content directory doesn't belong in a view body.
                LabeledContent("Cached data size",
                               value: dataSize.map(formatByteSize) ?? "Calculating…")
                Button("Clear History", role: .destructive) {
                    store.clearHistory()
                    Task { dataSize = await store.computeTotalDataSize() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 420)
        .task { dataSize = await store.computeTotalDataSize() }
        // settings.historyLimit no longer needs manual syncing here — the
        // store subscribes to it via AppState (single source of truth).
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier
        else { return }
        if !settings.excludedBundleIDs.contains(bid) {
            settings.excludedBundleIDs.append(bid)
        }
    }
}

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let store: Store

    public init(settings: Settings, store: Store) {
        self.settings = settings
        self.store = store
    }

    public func show() {
        if window == nil {
            let view = SettingsView(settings: settings, store: store)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Clap Settings"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
