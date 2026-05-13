import Foundation

/// Bundles Halo's rolling log file (and the previous-rotation copy, if
/// present) into a single text file the user can attach to a bug report.
///
/// Unlike the previous implementation, this does NOT shell out to the
/// `log` CLI — `log show` against the unified archive fails on macOS 26
/// in certain configurations. Reading our own file is always reliable.
public enum DiagnosticLog {
    public enum ExportError: Error, LocalizedError {
        case noDownloads
        case noLogYet
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noDownloads:
                return "Could not locate the user's Downloads folder."
            case .noLogYet:
                return "No log entries have been recorded yet — try summoning Halo or interacting with Settings first."
            case .writeFailed(let msg):
                return "Failed to write diagnostic file: \(msg)."
            }
        }
    }

    /// Concatenate the current log file (and the rotated previous one, if
    /// any) into `~/Downloads/Halo-diagnostic-<timestamp>.log`. Returns
    /// the destination URL.
    public static func export() throws -> URL {
        guard let downloads = FileManager.default.urls(
            for: .downloadsDirectory, in: .userDomainMask
        ).first else {
            throw ExportError.noDownloads
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let dest = downloads.appendingPathComponent("Halo-diagnostic-\(stamp).log")

        var body = Data()
        if let header = makeHeader().data(using: .utf8) {
            body.append(header)
        }

        // Older rotated chunk first so the file reads chronologically.
        let rotated = HaloLog.rotatedLogFileURL
        if FileManager.default.fileExists(atPath: rotated.path),
           let chunk = try? Data(contentsOf: rotated) {
            body.append("\n===== halo.log.1 (rotated) =====\n".data(using: .utf8) ?? Data())
            body.append(chunk)
        }

        if FileManager.default.fileExists(atPath: HaloLog.logFileURL.path),
           let chunk = try? Data(contentsOf: HaloLog.logFileURL) {
            body.append("\n===== halo.log (current) =====\n".data(using: .utf8) ?? Data())
            body.append(chunk)
        } else if !FileManager.default.fileExists(atPath: rotated.path) {
            throw ExportError.noLogYet
        }

        do {
            try body.write(to: dest)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        HaloLog.lifecycle.info("Diagnostic log exported to \(dest.path)")
        return dest
    }

    private static func makeHeader() -> String {
        """
        ===== Halo diagnostic =====
        Generated: \(Date())
        Halo version: \(Halo.version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Hardware: \(hardwareIdentifier())
        Log path: \(HaloLog.logFileURL.path)
        ===========================
        """
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
