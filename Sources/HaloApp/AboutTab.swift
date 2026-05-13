import SwiftUI
import HaloCore

/// About section in the v1.1 sidebar Settings panel. Phase 6 polishes the
/// logo and metadata grid — this is the initial extracted shape.
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("Halo").font(.largeTitle).bold()
                Text("v\(Halo.version)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Radial app launcher for macOS — point a direction, switch apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 12) {
                Link("GitHub", destination: URL(string: "https://github.com/elonnzhang/Halo")!)
                Text("·").foregroundStyle(.tertiary)
                Link("License (MIT)", destination: URL(string: "https://github.com/elonnzhang/Halo/blob/main/LICENSE")!)
            }
            .font(.callout)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
