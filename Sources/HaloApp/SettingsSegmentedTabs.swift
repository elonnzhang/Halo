import AppKit
import SwiftUI

/// A shared native segmented control for the General groups and Apps
/// profiles. Explicit fill distribution keeps each segment's gesture region
/// aligned with its label, including the profile drag/rename overlays.
struct SettingsSegmentedTabs: NSViewRepresentable {
    let labels: [String]
    let selectedIndex: Int
    let accessibilityLabel: String
    let onSelect: (Int) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        control.controlSize = .regular
        control.font = .systemFont(ofSize: 13, weight: .medium)
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        if control.segmentCount != labels.count { control.segmentCount = labels.count }
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
        }
        control.selectedSegment = selectedIndex
        control.setAccessibilityLabel(accessibilityLabel)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        init(onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }
        @objc func select(_ control: NSSegmentedControl) {
            guard control.selectedSegment >= 0 else { return }
            onSelect(control.selectedSegment)
        }
    }
}

/// Both settings pages use the same pinned, centred top row. Profile
/// management lives below it so adding profiles never shifts the tabs.
struct SettingsTabsHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: 360, height: 28)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}
