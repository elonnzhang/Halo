import Foundation
import AppKit
import ServiceManagement

/// Manages the Halo LaunchAgent so the user can opt into auto-launch on login.
///
/// Uses SMAppService.mainApp (macOS 13+) when available — that's the modern,
/// sandbox-friendly API. Falls back to writing the plist by hand for older systems.
@MainActor
enum LaunchAgentManager {
    static func apply(enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                NSLog("Halo: failed to \(enabled ? "register" : "unregister") login item: \(error)")
            }
        } else {
            legacyApply(enabled: enabled)
        }
    }

    @available(macOS, deprecated: 13.0, message: "Use SMAppService")
    private static func legacyApply(enabled: Bool) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.halo.launcher.plist")
        if enabled {
            let executable = Bundle.main.executablePath ?? ""
            let plist: [String: Any] = [
                "Label": "com.halo.launcher",
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            try? (plist as NSDictionary).write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
