import Foundation

/// Platform contract for executing a HaloAction. Lives in HaloCore so unit
/// tests can substitute a fake runtime; the AppKit-backed `live` impl lives
/// in HaloUI alongside `NSWorkspaceRuntime`.
public protocol ActionRuntime: Sendable {
    /// Open a filesystem URL (folder or file). Returns false if the URL
    /// doesn't resolve, is not on disk, or `NSWorkspace.open` reports failure.
    func openFile(at url: URL) -> Bool

    /// Open any non-file URL via `NSWorkspace.open`. The `shortcuts://`
    /// scheme goes through here so `runShortcut` reuses the same primitive.
    func openURL(_ url: URL) -> Bool
}

public enum ActionOutcome: Equatable, Sendable {
    case executed
    case failed
}

public struct ActionExecutor: Sendable {
    private let runtime: ActionRuntime

    public init(runtime: ActionRuntime) {
        self.runtime = runtime
    }

    @discardableResult
    public func execute(_ action: HaloAction) -> ActionOutcome {
        switch action.kind {
        case .openFolder:
            // Expand `~` so the user can store paths like `~/Code` literally.
            let expanded = (action.payload as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            let ok = runtime.openFile(at: url)
            HaloLog.switcher.info("action openFolder \(action.payload) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .openURL:
            guard let url = URL(string: action.payload) else {
                HaloLog.switcher.info("action openURL \(action.payload) → FAILED (parse)")
                return .failed
            }
            let ok = runtime.openURL(url)
            HaloLog.switcher.info("action openURL \(action.payload) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .runShortcut:
            // `shortcuts://run-shortcut?name=<name>` — system handles
            // permission prompt and "shortcut not found" UI. We treat
            // URL-open success as success; if the Shortcuts app pops a
            // "not found" toast that's its surface, not ours. `URLComponents`
            // takes care of percent-encoding the query value, including the
            // reserved `&` and `=` characters that bare `.urlQueryAllowed`
            // would let through.
            let trimmed = action.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                HaloLog.switcher.info("action runShortcut \(action.payload) → FAILED (empty)")
                return .failed
            }
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: trimmed)]
            guard let url = components.url else {
                HaloLog.switcher.info("action runShortcut \(action.payload) → FAILED (encode)")
                return .failed
            }
            let ok = runtime.openURL(url)
            HaloLog.switcher.info("action runShortcut \(action.payload) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed
        }
    }
}
