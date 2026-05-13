import AppKit
import SwiftUI

/// Tiny modal-ish picker that appears when the user commits onto an empty slot.
/// Hosted in its own NSWindow so it doesn't depend on the Settings tab being open.
@MainActor
final class PinPickerWindowController {
    private var window: NSWindow?
    private var completion: ((String?) -> Void)?

    func show(forSlot slot: Int, completion: @escaping (String?) -> Void) {
        self.completion = completion
        let host = NSHostingController(rootView: PinPickerView(slot: slot) { [weak self] picked in
            self?.completion?(picked)
            self?.close()
        })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Pin to slot \(slot)"
        w.contentViewController = host
        w.isReleasedWhenClosed = false

        // Centre on the screen the cursor is currently on — multi-display
        // users expect the picker to land on their active display, not
        // always on `NSScreen.main`.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = w.frame.size
            w.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }

        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        self.window = w
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct PinPickerView: View {
    let slot: Int
    let onPick: (String?) -> Void
    @State private var apps: [Item] = []
    @State private var search = ""

    struct Item: Identifiable, Hashable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
        let url: URL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                Button("Cancel") { onPick(nil) }
            }
            .padding(12)
            Divider()
            List(filtered, id: \.bundleID) { item in
                Button {
                    onPick(item.bundleID)
                } label: {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.bundleID)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        // Without an explicit frame the NSHostingController collapses to
        // its content's intrinsic size — for an empty List that's zero,
        // and the window winds up showing nothing but the traffic-light
        // chrome and a single search-field row.
        .frame(width: 480, height: 520)
        .onAppear(perform: load)
    }

    private var filtered: [Item] {
        guard !search.isEmpty else { return apps }
        let q = search.lowercased()
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    private func load() {
        var seen: Set<String> = []
        var out: [Item] = []
        let paths = ["/Applications", "/System/Applications"]
        for path in paths {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier,
                      !seen.contains(bid)
                else { continue }
                seen.insert(bid)
                let name = (url.lastPathComponent as NSString).deletingPathExtension
                out.append(Item(bundleID: bid, name: name, url: url))
            }
        }
        apps = out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
