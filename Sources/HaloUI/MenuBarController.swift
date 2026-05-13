import AppKit

@MainActor
public final class MenuBarController {
    public let statusItem: NSStatusItem
    private let menu = NSMenu()

    public init(onSummon: @escaping () -> Void,
                onSettings: @escaping () -> Void,
                onQuit: @escaping () -> Void)
    {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Glyph: ring-with-dot, the Halo mark.
            button.image = NSImage(systemSymbolName: "circle.dashed.inset.filled",
                                   accessibilityDescription: "Halo")
            button.image?.isTemplate = true
        }

        let summon = NSMenuItem(title: "Summon Halo", action: #selector(MenuBox.fire(_:)), keyEquivalent: "")
        let settings = NSMenuItem(title: "Settings…", action: #selector(MenuBox.fire(_:)), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit Halo", action: #selector(MenuBox.fire(_:)), keyEquivalent: "q")

        let box = MenuBox(onSummon: onSummon, onSettings: onSettings, onQuit: onQuit)
        summon.target = box; summon.representedObject = HaloMenuAction.summon
        settings.target = box; settings.representedObject = HaloMenuAction.settings
        quit.target = box; quit.representedObject = HaloMenuAction.quit
        self.menuBox = box

        menu.addItem(summon)
        menu.addItem(.separator())
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private var menuBox: MenuBox?
}

private enum HaloMenuAction {
    case summon, settings, quit
}

private final class MenuBox: NSObject {
    let onSummon: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    init(onSummon: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void)
    {
        self.onSummon = onSummon
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    @objc func fire(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? HaloMenuAction else { return }
        switch action {
        case .summon: onSummon()
        case .settings: onSettings()
        case .quit: onQuit()
        }
    }
}
