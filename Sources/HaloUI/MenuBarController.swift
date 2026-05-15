import AppKit

@MainActor
public final class MenuBarController {
    public let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let profileMenu = NSMenu()
    private let profileItem: NSMenuItem
    private let menuBox: MenuBox

    public init(onSummon: @escaping () -> Void,
                onSettings: @escaping () -> Void,
                onProfileSelect: @escaping (UUID) -> Void,
                onQuit: @escaping () -> Void)
    {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Glyph: ring-with-dot, the Halo mark.
            button.image = NSImage(systemSymbolName: "circle.dashed.inset.filled",
                                   accessibilityDescription: "Halo")
            button.image?.isTemplate = true
        }

        let box = MenuBox(
            onSummon: onSummon,
            onSettings: onSettings,
            onProfileSelect: onProfileSelect,
            onQuit: onQuit
        )
        menuBox = box

        let summon = NSMenuItem(title: "Summon Halo",
                                action: #selector(MenuBox.fire(_:)),
                                keyEquivalent: "")
        summon.target = box
        summon.representedObject = HaloMenuAction.summon

        profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = profileMenu

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(MenuBox.fire(_:)),
                                  keyEquivalent: ",")
        settings.target = box
        settings.representedObject = HaloMenuAction.settings

        let quit = NSMenuItem(title: "Quit Halo",
                              action: #selector(MenuBox.fire(_:)),
                              keyEquivalent: "q")
        quit.target = box
        quit.representedObject = HaloMenuAction.quit

        menu.addItem(summon)
        menu.addItem(.separator())
        menu.addItem(profileItem)
        menu.addItem(.separator())
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        statusItem.menu = menu
    }

    /// Rebuild the Profile submenu. Caller (AppDelegate) invokes from
    /// `applyPreferences()` so the list stays fresh on every prefs change
    /// (add / rename / delete / switch). Avoids NSMenuDelegate's
    /// non-isolated callback path.
    ///
    /// If there's only one profile, the parent item is hidden — the
    /// submenu has nothing useful to switch to.
    public func setProfiles(_ entries: [(id: UUID, name: String, isActive: Bool)]) {
        profileMenu.removeAllItems()
        for entry in entries {
            let item = NSMenuItem(title: entry.name,
                                  action: #selector(MenuBox.fireProfile(_:)),
                                  keyEquivalent: "")
            item.target = menuBox
            item.representedObject = entry.id
            item.state = entry.isActive ? .on : .off
            profileMenu.addItem(item)
        }
        profileItem.isHidden = entries.count <= 1
    }
}

private enum HaloMenuAction {
    case summon, settings, quit
}

@MainActor
private final class MenuBox: NSObject {
    let onSummon: () -> Void
    let onSettings: () -> Void
    let onProfileSelect: (UUID) -> Void
    let onQuit: () -> Void

    init(onSummon: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onProfileSelect: @escaping (UUID) -> Void,
         onQuit: @escaping () -> Void)
    {
        self.onSummon = onSummon
        self.onSettings = onSettings
        self.onProfileSelect = onProfileSelect
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

    @objc func fireProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onProfileSelect(id)
    }
}
