import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// The three UX moments Halo plays a sound for.
///
/// Names match the user-visible feature ("召唤 / 切换 / 滑动") rather than the
/// macOS system sound they map to internally, so we can swap in custom
/// `.aiff` assets later without renaming the call sites.
public enum HaloSoundEffect: String, Sendable, CaseIterable {
    /// Halo appears on screen.
    case summon
    /// User commits a slot — the actual app switch fires.
    case commit
    /// Highlighted slot moves (scroll wheel or arrow key tick).
    case slide

    /// macOS built-in sound name. Cheap, no resources to ship.
    var systemSoundName: String {
        switch self {
        case .summon: return "Glass"
        case .commit: return "Pop"
        case .slide:  return "Tink"
        }
    }
}

/// Plays the three UX sounds. Reads the live `AppPreferences.shared` toggle
/// on every call so flipping it in Settings takes effect immediately.
///
/// `NSSound.play()` is fire-and-forget; we copy the cached instance per call
/// so rapid `.slide` ticks during a fast scroll overlap naturally instead of
/// the second tick silently aborting because the previous play is still in
/// flight.
@MainActor
public final class SoundEffectPlayer {
    public static let shared = SoundEffectPlayer()

    private var cache: [HaloSoundEffect: Any] = [:]

    public init() {}

    public func play(_ effect: HaloSoundEffect) {
        guard AppPreferences.shared.soundEffectsEnabled else { return }
        #if canImport(AppKit)
        let template: NSSound
        if let cached = cache[effect] as? NSSound {
            template = cached
        } else if let sound = NSSound(named: NSSound.Name(effect.systemSoundName)) {
            cache[effect] = sound
            template = sound
        } else {
            return
        }
        // Copy so the next tick of the same effect can overlap without the
        // currently-playing instance cutting itself off mid-decay.
        let instance = (template.copy() as? NSSound) ?? template
        instance.play()
        #endif
    }
}
