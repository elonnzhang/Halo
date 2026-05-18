import Foundation
import os.signpost

/// Performance instrumentation for hot launch paths and grid setup.
///
/// Two output channels:
///   1. `OSSignposter` under `com.halo.launcher / perf` — zero-cost when
///      Instruments isn't recording. Open Instruments → Logging template
///      and filter to the `perf` category to see flame charts.
///   2. Text log via `HaloLog.perf`, gated on the `HALO_PERF_LOG`
///      environment variable (`=1` to enable). When on, every measured
///      section emits one line like `[perf] refreshSlots 312.4 ms`.
///      Read from `Console.app` or `~/Library/Logs/Halo/halo.log`.
public enum PerfSignpost {
    private static let signposter = OSSignposter(
        subsystem: HaloLog.subsystem,
        category: "perf"
    )

    /// Honoured only on first read so toggling the env var mid-session
    /// behaves predictably and `getenv` doesn't show up in hot paths.
    public static let textLogEnabled: Bool = {
        guard let raw = ProcessInfo.processInfo.environment["HALO_PERF_LOG"]
        else { return false }
        return raw == "1" || raw.lowercased() == "true" || raw.lowercased() == "yes"
    }()

    /// Synchronous measurement. Pass a static name so signpost intervals
    /// group correctly in Instruments.
    @discardableResult
    public static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = textLogEnabled ? DispatchTime.now() : nil
        defer {
            signposter.endInterval(name, state)
            if let start {
                logElapsed(name, since: start)
            }
        }
        return try body()
    }

    /// Async variant. Same shape as `measure`, but lets the caller suspend
    /// inside `body` without forfeiting the interval.
    @discardableResult
    public static func measureAsync<T>(
        _ name: StaticString,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = textLogEnabled ? DispatchTime.now() : nil
        defer {
            signposter.endInterval(name, state)
            if let start {
                logElapsed(name, since: start)
            }
        }
        return try await body()
    }

    /// Plain event marker — use when the work isn't a single contiguous
    /// span (e.g. "first-frame painted" inside an async pipeline).
    public static func event(_ name: StaticString, _ message: String = "") {
        if message.isEmpty {
            signposter.emitEvent(name)
        } else {
            signposter.emitEvent(name, "\(message)")
        }
        if textLogEnabled {
            HaloLog.perf.info("event \(name) \(message)")
        }
    }

    private static func logElapsed(_ name: StaticString, since start: DispatchTime) {
        let end = DispatchTime.now()
        let nanos = end.uptimeNanoseconds &- start.uptimeNanoseconds
        let ms = Double(nanos) / 1_000_000.0
        HaloLog.perf.info(String(format: "%@ %.2f ms", String(describing: name), ms))
    }
}
