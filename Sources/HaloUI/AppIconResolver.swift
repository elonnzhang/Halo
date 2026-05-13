import AppKit

public enum AppIconResolver {
    public static func icon(for bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    public static func frontmostIcon() -> NSImage? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier
        else { return nil }
        return icon(for: id)
    }
}
