import Foundation
import os.log

/// Halo's logging facility. Each line is tee'd into two places:
///
/// 1. `os.Logger` under the `com.halo.launcher` subsystem — visible live
///    via `log stream --predicate 'subsystem == "com.halo.launcher"'` or
///    Console.app while developing.
/// 2. A plain-text file at `~/Library/Logs/Halo/halo.log` — survives
///    process death and is what `DiagnosticLog.export()` ships to the
///    user. We can't rely on `log show` against the unified log archive
///    (macOS 26 returns "Could not open local log store" on some
///    machines), so the file is the source of truth for diagnostics.
///
/// File rotation: when `halo.log` exceeds 5 MB it's renamed to
/// `halo.log.1` and a fresh `halo.log` starts. The export bundles both.
public enum HaloLog {
    public static let subsystem = "com.halo.launcher"

    public static let lifecycle  = HaloLogger(category: "lifecycle")
    public static let hotkey     = HaloLogger(category: "hotkey")
    public static let summon     = HaloLogger(category: "summon")
    public static let switcher   = HaloLogger(category: "switcher")
    public static let identity   = HaloLogger(category: "identity")
    public static let usage      = HaloLogger(category: "usage")
    public static let settings   = HaloLogger(category: "settings")
    public static let onboarding = HaloLogger(category: "onboarding")

    /// Where the live log file lives. Created lazily on first write.
    public static let logFileURL: URL = {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/Halo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("halo.log")
    }()

    /// Rotated copy of the previous logFile when size cap is hit.
    public static var rotatedLogFileURL: URL {
        logFileURL.appendingPathExtension("1")
    }

    private static let lock = NSLock()
    /// `ISO8601DateFormatter` is documented thread-safe for `string(from:)`
    /// since macOS 10.12, and we further serialize writes with `lock`, so
    /// the unchecked annotation is safe in practice.
    nonisolated(unsafe) private static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let maxBytes: UInt64 = 5_000_000

    static func appendFile(level: String, category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }

        rotateIfNeeded()

        let stamp = timestamp.string(from: Date())
        let levelPad = level.padding(toLength: 5, withPad: " ", startingAt: 0)
        let line = "\(stamp) [\(levelPad)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }

    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxBytes
        else { return }
        try? FileManager.default.removeItem(at: rotatedLogFileURL)
        try? FileManager.default.moveItem(at: logFileURL, to: rotatedLogFileURL)
    }
}

/// One category-tagged logger. Calls fan out to `os.Logger` and to the
/// rolling file at `HaloLog.logFileURL`. Safe to call from any thread.
public struct HaloLogger: Sendable {
    public let category: String
    private let osLogger: Logger

    public init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: HaloLog.subsystem, category: category)
    }

    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        HaloLog.appendFile(level: "INFO", category: category, message: message)
    }

    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        HaloLog.appendFile(level: "ERROR", category: category, message: message)
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        HaloLog.appendFile(level: "DEBUG", category: category, message: message)
    }
}
