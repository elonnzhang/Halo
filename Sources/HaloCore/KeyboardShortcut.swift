import Foundation
import CoreGraphics

/// Parsed representation of a user-typed key combo like `"cmd+shift+n"`,
/// `"⌃⌥F"`, or `"ctrl+space"`. The executor pipes this to `CGEvent.post`
/// to send the keystroke to a target app.
public struct KeyboardShortcut: Equatable, Sendable {
    /// `CGKeyCode` (== UInt16). Stored unbridged so the type stays Sendable
    /// without importing CoreGraphics in tests that only consume the value.
    public let keyCode: UInt16
    /// `CGEventFlags.rawValue`. Bit 17 = Command, bit 18 = Shift,
    /// bit 19 = Option/Alt, bit 20 = Control. Constants:
    /// `.maskCommand` = 0x100000, `.maskShift` = 0x20000,
    /// `.maskAlternate` = 0x80000, `.maskControl` = 0x40000.
    public let modifierMask: UInt64

    public init(keyCode: UInt16, modifierMask: UInt64) {
        self.keyCode = keyCode
        self.modifierMask = modifierMask
    }

    /// Permissive parser. Accepts:
    ///   - `cmd+shift+n` — English tokens with `+` / `-` / space separators
    ///   - `⌃⌥F` — symbol modifiers packed against the key
    ///   - mixed forms like `cmd+⇧+n`
    /// Returns nil for empty input, unknown key glyphs, or two non-modifier tokens.
    public static func parse(_ input: String) -> KeyboardShortcut? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var flags: UInt64 = 0
        var working = trimmed

        // Peel symbol-form modifier glyphs off the front. `⌃⌥F` becomes
        // flags = ctrl|opt with working = "F".
        while let first = working.first, let mask = symbolMask(first) {
            flags |= mask
            working = String(working.dropFirst())
        }

        let parts = working
            .split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " })
            .filter { !$0.isEmpty }

        var keyToken: String?
        for part in parts {
            let token = String(part)
            let lower = token.lowercased()
            if let mod = modifierMask(for: lower) {
                flags |= mod
            } else if token.count == 1, let first = token.first, let mask = symbolMask(first) {
                // Inline symbol modifier inside an otherwise tokenised form.
                flags |= mask
            } else if keyToken == nil {
                keyToken = lower
            } else {
                return nil
            }
        }

        guard let key = keyToken, let kc = keyCode(for: key) else { return nil }
        return KeyboardShortcut(keyCode: kc, modifierMask: flags)
    }

    private static func symbolMask(_ glyph: Character) -> UInt64? {
        switch glyph {
        case "⌘": return 0x100000
        case "⇧": return 0x020000
        case "⌥": return 0x080000
        case "⌃": return 0x040000
        default: return nil
        }
    }

    private static func modifierMask(for token: String) -> UInt64? {
        switch token {
        case "cmd", "command": return 0x100000
        case "shift":          return 0x020000
        case "opt", "option", "alt": return 0x080000
        case "ctrl", "control": return 0x040000
        default: return nil
        }
    }

    /// Maps a single-character or named key to a virtual key code.
    /// Covers the ASCII alphabet, digit row, and the most common named
    /// keys; F1..F12 included so the user can bind window-management
    /// combos that often use function keys.
    private static func keyCode(for token: String) -> UInt16? {
        switch token {
        // Letters (US layout virtual codes)
        case "a": return 0;  case "b": return 11; case "c": return 8;  case "d": return 2
        case "e": return 14; case "f": return 3;  case "g": return 5;  case "h": return 4
        case "i": return 34; case "j": return 38; case "k": return 40; case "l": return 37
        case "m": return 46; case "n": return 45; case "o": return 31; case "p": return 35
        case "q": return 12; case "r": return 15; case "s": return 1;  case "t": return 17
        case "u": return 32; case "v": return 9;  case "w": return 13; case "x": return 7
        case "y": return 16; case "z": return 6
        // Digits
        case "1": return 18; case "2": return 19; case "3": return 20; case "4": return 21
        case "5": return 23; case "6": return 22; case "7": return 26; case "8": return 28
        case "9": return 25; case "0": return 29
        // Named keys
        case "space":  return 49
        case "return", "enter": return 36
        case "tab":    return 48
        case "escape", "esc": return 53
        case "delete", "backspace": return 51
        case "forwarddelete", "fwddelete", "fdel": return 117
        case "left",   "←": return 123
        case "right",  "→": return 124
        case "down",   "↓": return 125
        case "up",     "↑": return 126
        case "comma":  return 43
        case "period", "dot": return 47
        case "slash":  return 44
        case "backslash": return 42
        case "semicolon": return 41
        case "quote":  return 39
        case "leftbracket":  return 33
        case "rightbracket": return 30
        case "minus":  return 27
        case "equal":  return 24
        case "grave":  return 50
        // F1..F12
        case "f1": return 122; case "f2": return 120; case "f3": return 99
        case "f4": return 118; case "f5": return 96;  case "f6": return 97
        case "f7": return 98;  case "f8": return 100; case "f9": return 101
        case "f10": return 109; case "f11": return 103; case "f12": return 111
        default: return nil
        }
    }

    /// Human-readable form for Settings preview: `⌘⌥N`, `⇧⌃F5`, etc.
    public var displaySymbols: String {
        var out = ""
        if modifierMask & 0x040000 != 0 { out += "⌃" }    // control
        if modifierMask & 0x080000 != 0 { out += "⌥" }    // option
        if modifierMask & 0x020000 != 0 { out += "⇧" }    // shift
        if modifierMask & 0x100000 != 0 { out += "⌘" }    // command
        out += keyGlyph
        return out
    }

    private var keyGlyph: String {
        // Reverse a subset — only the keys the user is likely to read
        // back. For everything else we return the virtual code as a
        // fallback `[kc:NN]` so the editor stays diagnosable.
        switch keyCode {
        case 0: return "A"; case 11: return "B"; case 8: return "C"; case 2: return "D"
        case 14: return "E"; case 3: return "F"; case 5: return "G"; case 4: return "H"
        case 34: return "I"; case 38: return "J"; case 40: return "K"; case 37: return "L"
        case 46: return "M"; case 45: return "N"; case 31: return "O"; case 35: return "P"
        case 12: return "Q"; case 15: return "R"; case 1: return "S"; case 17: return "T"
        case 32: return "U"; case 9: return "V"; case 13: return "W"; case 7: return "X"
        case 16: return "Y"; case 6: return "Z"
        case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
        case 23: return "5"; case 22: return "6"; case 26: return "7"; case 28: return "8"
        case 25: return "9"; case 29: return "0"
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 53: return "⎋"
        case 51: return "⌫"
        case 117: return "⌦"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"
        case 118: return "F4"; case 96: return "F5"; case 97: return "F6"
        case 98: return "F7"; case 100: return "F8"; case 101: return "F9"
        case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        default: return "[kc:\(keyCode)]"
        }
    }
}
