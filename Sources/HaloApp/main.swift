import AppKit
import SwiftUI
import HaloCore
import HaloUI

// Classic AppKit bootstrap. We tried `@main struct App` with a SwiftUI
// `Settings { … }` scene, but with `LSUIElement = true` (which Halo needs
// to be menu-bar-only) the scene refuses to surface its window even after
// flipping activation policy — `sendAction(showSettingsWindow:)` finds no
// handler in the responder chain. `SettingsWindowController` (in
// `SettingsWindow.swift`) hosts the same `SettingsRootView` via
// `NSHostingController` and is reliable.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
