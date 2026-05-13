import SwiftUI

// MARK: - macOS 12 compatibility shims
//
// Halo targets macOS 12+. A handful of SwiftUI APIs we'd otherwise use were
// added in 13 / 14. These shims keep the call sites readable while routing
// older platforms to the closest equivalent.

/// `formStyle(.grouped)` on macOS 13+, plain `Form` (no modifier) on 12.
public struct CompatGroupedFormStyle: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}

public extension View {
    func compatGroupedFormStyle() -> some View {
        modifier(CompatGroupedFormStyle())
    }

    /// `onChange(of:)` trailing closure on macOS 14+, single-arg
    /// `onChange(of:perform:)` on older.
    @ViewBuilder
    func compatOnChange<V: Equatable>(
        of value: V,
        perform: @escaping (V) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, new in perform(new) }
        } else {
            self.onChange(of: value, perform: perform)
        }
    }
}

/// `NavigationStack` on macOS 13+, `NavigationView` on 12. The latter is
/// deprecated in newer SDKs but still functions and is the only fallback for
/// `.searchable` placement to behave correctly on 12.
@MainActor
public struct CompatNavigationContainer<Content: View>: View {
    @ViewBuilder public var content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    public var body: some View {
        if #available(macOS 13.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
        }
    }
}
