import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Recommended bundle IDs for the Settings → Whitelist "Apply recommended"
/// button. The list is intentionally tilted toward apps where ⌥-chords are
/// load-bearing (IDEs, design, 3D, remote desktop). Sourced from
/// docs/SETTING.md §4.4.
public enum WhitelistSuggestions {
    public static let curated: [String] = [
        // Apple IDE
        "com.apple.dt.Xcode",
        // VS Code family
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.vscodium",
        // JetBrains
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.WebStorm",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.AppCode",
        // Design
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.adobe.illustrator",
        "com.adobe.Photoshop",
        // 3D / game engines
        "org.blenderfoundation.blender",
        "com.unity3d.UnityEditor5.x",
        "com.Roblox.RobloxStudio",
        // Remote desktop / virtualization
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "com.microsoft.rdc.macos",
    ]

    #if canImport(AppKit)
    /// Subset of `curated` whose app is currently installed on the user's
    /// system. We avoid seeding bundle IDs that resolve to a missing icon
    /// so the Whitelist tab never shows ghost rows.
    @MainActor
    public static func installedSubset() -> [String] {
        curated.filter { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
    }
    #endif
}
