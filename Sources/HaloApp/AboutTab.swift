import AppKit
import SwiftUI
import HaloCore

/// About section in the v1.1 sidebar Settings panel. Matches mockup §5:
/// gradient app-icon badge, version + monospaced build tag, tagline,
/// links, metadata grid, and an Export Diagnostic Log shortcut so users
/// filing bugs aren't forced back to the General tab.
struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 24)

                logoBadge
                    .frame(width: 96, height: 96)

                Text("Halo")
                    .font(.system(size: 26, weight: .bold))

                Text("v\(Halo.version)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("Radial app launcher for macOS — point a direction, switch apps.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                HStack(spacing: 8) {
                    Link("GitHub", destination: URL(string: "https://github.com/elonnzhang/Halo")!)
                    Text("·").foregroundStyle(.tertiary)
                    Link("License (MIT)", destination: URL(string: "https://github.com/elonnzhang/Halo/blob/main/LICENSE")!)
                }
                .font(.system(size: 12))

                metadataGrid
                    .padding(.top, 6)

                Button("Export diagnostic log…") {
                    exportDiagnostics()
                }
                .padding(.top, 6)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var logoBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.04, green: 0.52, blue: 1.00),
                            Color(red: 0.69, green: 0.32, blue: 0.87),
                            Color(red: 1.00, green: 0.18, blue: 0.33),
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 0.69, green: 0.32, blue: 0.87).opacity(0.3),
                        radius: 12, y: 6)
            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            metaRow("Swift", "6.0 · macOS 12+ universal")
            metaRow("Bundle ID", Bundle.main.bundleIdentifier ?? "—")
            metaRow("Subsystem", "app.halo / unified log")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.tertiary).frame(width: 80, alignment: .leading)
            Text(value)
        }
    }

    private func exportDiagnostics() {
        do {
            let url = try DiagnosticLog.export()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Could not export diagnostic log",
                comment: "Alert title shown when log export fails"
            )
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
        }
    }
}
