import AppKit
import HaloCore

/// AppKit-backed `ActionRuntime`. HaloCore stays AppKit-free so unit tests
/// don't drag the UI layer; the live impl lives here next to
/// `NSWorkspaceRuntime`.
public struct NSWorkspaceActionRuntime: ActionRuntime {
    public init() {}

    public func openFile(at url: URL) -> Bool {
        // `NSWorkspace.open(_:)` synchronously returns whether the OS
        // accepted the open request. We additionally check the path
        // exists — open() returns true for a non-existent file when the
        // default app for the parent extension is willing to launch with
        // an empty arg, which would mask "user typed a stale path".
        guard FileManager.default.fileExists(atPath: url.path) else {
            HaloLog.switcher.info("action openFile missing path \(url.path)")
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    public func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

extension ActionExecutor {
    /// Factory for the production macOS runtime.
    public static func live() -> ActionExecutor {
        ActionExecutor(runtime: NSWorkspaceActionRuntime())
    }
}
