import AppKit
import SwiftUI
import HaloCore
import HaloUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
