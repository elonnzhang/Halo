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
        let host = NSHostingController(rootView: PinPickerView { [weak self] picked in
            self?.completion?(picked)
            self?.close()
        })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = String.localizedStringWithFormat(
            NSLocalizedString("Pin to slot %d", comment: "Pin picker window title"),
            slot
        )
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

/// Live empty-slot picker body. Thin host around the shared `AppListPicker`;
/// the window chrome + "Pin to slot N" title come from
/// `PinPickerWindowController`.
private struct PinPickerView: View {
    let onPick: (String?) -> Void

    var body: some View {
            AppListPicker(onPick: onPick)
            // Explicit frame: the NSHostingController would otherwise collapse
            // to the content's intrinsic size and the window would show only
            // chrome + the search row.
            .frame(width: 560, height: 640)
    }
}
