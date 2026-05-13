import Foundation
import Carbon.HIToolbox
import AppKit

/// Global hotkey monitor that emits an engaged/released pair.
///
/// Uses Carbon `RegisterEventHotKey` (no Accessibility permission needed).
/// Halo is summoned immediately on press (`.holdEngaged`) and committed on
/// release (`.holdReleased`) — the earlier 200ms long-press / short-tap split
/// has been removed in favour of instant-summon.
@MainActor
public final class HaloHotkey {
    public enum Event {
        case holdEngaged
        case holdReleased
    }

    private var hotKeyRef: EventHotKeyRef?
    private var listener: ((Event) -> Void)?
    private var holdEngaged = false
    private static var registry: [UInt32: HaloHotkey] = [:]
    private static var nextID: UInt32 = 1
    private var assignedID: UInt32 = 0
    private static var handlerInstalled = false

    public init() {}

    // Note: callers must explicitly unregister(); deinit cannot touch MainActor state.

    /// Register a hotkey chord. Returns `false` if registration fails (typically: the
    /// chord is already claimed by another app).
    @discardableResult
    public func register(keyCode: UInt32, carbonModifiers: UInt32,
                         listener: @escaping (Event) -> Void) -> Bool
    {
        // If a previous registration exists, drop it before claiming a new chord.
        if hotKeyRef != nil { unregister() }

        self.listener = listener
        Self.installHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID += 1
        assignedID = id
        Self.registry[id] = self

        var ref: EventHotKeyRef?
        let signature: UInt32 = 0x48414C4F // 'HALO'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)

        let status = RegisterEventHotKey(
            keyCode, carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status != noErr {
            Self.registry.removeValue(forKey: id)
            return false
        }
        hotKeyRef = ref
        return true
    }

    /// Convenience: register ⌘⌥Space.
    @discardableResult
    public func registerDefault(listener: @escaping (Event) -> Void) -> Bool {
        register(keyCode: UInt32(kVK_Space),
                 carbonModifiers: UInt32(cmdKey | optionKey),
                 listener: listener)
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        Self.registry.removeValue(forKey: assignedID)
    }

    // MARK: - Internal callbacks

    fileprivate func handlePress() {
        // Instant summon: fire engaged synchronously on press. No threshold, no
        // short-tap quick-swap branch.
        holdEngaged = true
        listener?(.holdEngaged)
    }

    fileprivate func handleRelease() {
        guard holdEngaged else { return }
        holdEngaged = false
        listener?(.holdReleased)
    }

    // MARK: - Carbon glue

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, _ -> OSStatus in
                guard let eventRef = eventRef else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let hotkey = HaloHotkey.registry[hotKeyID.id]
                else { return noErr }

                let kind = GetEventKind(eventRef)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if kind == UInt32(kEventHotKeyPressed) {
                            hotkey.handlePress()
                        } else if kind == UInt32(kEventHotKeyReleased) {
                            hotkey.handleRelease()
                        }
                    }
                }
                return noErr
            },
            specs.count,
            &specs,
            nil,
            nil
        )
    }
}
