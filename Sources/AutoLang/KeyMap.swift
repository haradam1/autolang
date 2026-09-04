import Foundation

/// Static transliteration table for the two standard macOS layouts we support:
/// U.S. English (ABC) and the standard Israeli Hebrew layout.
///
/// The insight the whole tool rests on: a physical key emits an English letter
/// *or* a Hebrew letter depending on the active input source. If you map the
/// hardware keycode (which is layout-independent) through both columns, you can
/// re-render a word the user typed in the "wrong" layout into the other one.
///
/// NOTE (Phase 2 generalization): this hardcodes the standard layouts. The
/// general path is `UCKeyTranslate` against the user's actually-installed
/// input sources, so custom/alternate layouts work too. Kept static here for a
/// deterministic, permission-free skeleton.
enum KeyMap {
    struct Entry {
        let en: Character
        let he: Character
    }

    /// virtual keycode (kVK_ANSI_*) -> (english char, hebrew char)
    static let table: [Int64: Entry] = [
        0x0C: Entry(en: "q", he: "/"),
        0x0D: Entry(en: "w", he: "'"),
        0x0E: Entry(en: "e", he: "ק"),
        0x0F: Entry(en: "r", he: "ר"),
        0x11: Entry(en: "t", he: "א"),
        0x10: Entry(en: "y", he: "ט"),
        0x20: Entry(en: "u", he: "ו"),
        0x22: Entry(en: "i", he: "ן"),
        0x1F: Entry(en: "o", he: "ם"),
        0x23: Entry(en: "p", he: "פ"),

        0x00: Entry(en: "a", he: "ש"),
        0x01: Entry(en: "s", he: "ד"),
        0x02: Entry(en: "d", he: "ג"),
        0x03: Entry(en: "f", he: "כ"),
        0x05: Entry(en: "g", he: "ע"),
        0x04: Entry(en: "h", he: "י"),
        0x26: Entry(en: "j", he: "ח"),
        0x28: Entry(en: "k", he: "ל"),
        0x25: Entry(en: "l", he: "ך"),
        0x29: Entry(en: ";", he: "ף"),
        0x27: Entry(en: "'", he: ","),

        0x06: Entry(en: "z", he: "ז"),
        0x07: Entry(en: "x", he: "ס"),
        0x08: Entry(en: "c", he: "ב"),
        0x09: Entry(en: "v", he: "ה"),
        0x0B: Entry(en: "b", he: "נ"),
        0x2D: Entry(en: "n", he: "מ"),
        0x2E: Entry(en: "m", he: "צ"),
        0x2B: Entry(en: ",", he: "ת"),
        0x2F: Entry(en: ".", he: "ץ"),
        0x2C: Entry(en: "/", he: ".")
    ]

    /// Keycodes that end a word (space, return, tab, etc.). Used for buffering.
    static let wordBoundaryKeycodes: Set<Int64> = [
        0x31, // space
        0x24, // return
        0x4C, // keypad enter
        0x30, // tab
        0x35  // escape
    ]

    static func entry(for keycode: Int64) -> Entry? { table[keycode] }

    /// Is this a keycode we know how to render in both languages?
    static func isMappable(_ keycode: Int64) -> Bool { table[keycode] != nil }

    /// Render a sequence of keystrokes as a string in the requested language.
    /// Shift state is applied as capitalization for English (Hebrew has no case).
    static func render(_ keystrokes: [Keystroke], as lang: Language) -> String {
        var out = ""
        for k in keystrokes {
            guard let e = table[k.code] else { continue }
            let ch = lang == .hebrew ? e.he : e.en
            if k.shifted, lang == .english {
                out += String(ch).uppercased()
            } else {
                out.append(ch)
            }
        }
        return out
    }
}

/// One physical key press: which key, and whether it was shifted (so we can
/// preserve the user's capitalization through a conversion or typo fix).
struct Keystroke {
    let code: Int64
    let shifted: Bool
}

enum Language {
    case english
    case hebrew

    var other: Language { self == .english ? .hebrew : .english }
    var badge: String { self == .hebrew ? "עב" : "EN" }
}
