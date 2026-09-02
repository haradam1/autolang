import Foundation
import CoreGraphics

/// Emits synthetic keystrokes: backspaces to erase what was typed, then the
/// corrected text as a unicode string. Requires Accessibility permission
/// (because it *posts* events, not just listens).
///
/// Every event we post is stamped with `AutoLangMagic` in the event's user-data
/// field so `EventTapController` can recognize and ignore its own output — vital,
/// since posted events re-enter our tap and would otherwise be re-buffered
/// (and worse, look like the user pressing backspace).
let AutoLangMagic: Int64 = 0x4155_544F // "AUTO"

final class TextInjector {
    private let source = CGEventSource(stateID: .combinedSessionState)
    private static let kVKDelete: CGKeyCode = 0x33

    /// Delete `count` characters, then type `text`.
    func replace(deleting count: Int, with text: String) {
        for _ in 0..<count { pressDelete() }
        typeString(text)
    }

    private func pressDelete() {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.kVKDelete, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.kVKDelete, keyDown: false)
        else { return }
        stamp(down); stamp(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Post `text` as a unicode string on a single synthetic key event. This
    /// bypasses the active layout, so we type Hebrew even while the ABC layout
    /// is momentarily active (we switch the source separately, afterward).
    private func typeString(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        stamp(event)
        event.post(tap: .cghidEventTap)

        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            stamp(up)
            up.post(tap: .cghidEventTap)
        }
    }

    private func stamp(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: AutoLangMagic)
    }
}
