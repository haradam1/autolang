import ApplicationServices
import AppKit

/// Reads the word under the text caret (via the Accessibility API) and reports
/// its language, so we can switch the input source to match when you navigate
/// back into a word to edit it — preventing mixed Hebrew/English words.
enum CaretLanguage {

    /// Language of the word at (or just left of) the caret in the focused text
    /// element. nil when it can't be determined (no text field, empty, etc.).
    static func atCaret() -> Language? {
        guard let (text, caret) = caretWindow() else { return nil }
        return wordLanguage(in: text, caret: caret)
    }

    // MARK: - Pure core (unit-tested)

    /// The language of the word containing (or immediately left of) `caret`,
    /// decided by the word's first alphabetic character.
    static func wordLanguage(in text: String, caret: Int) -> Language? {
        let chars = Array(text)
        let n = chars.count
        guard n > 0 else { return nil }

        // Pick the character to anchor on: the one under the caret, or — if the
        // caret sits at the end or on a non-word char — the one just to its left.
        var pos = min(max(caret, 0), n)
        if pos >= n || !isWordChar(chars[pos]) { pos -= 1 }
        guard pos >= 0, pos < n, isWordChar(chars[pos]) else { return nil }

        // Walk to the word's start, then return the first alphabetic char's language.
        var start = pos
        while start > 0, isWordChar(chars[start - 1]) { start -= 1 }
        var k = start
        while k < n, isWordChar(chars[k]) {
            if let lang = language(of: chars[k]) { return lang }
            k += 1
        }
        return nil
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c == "'" || c == "\u{2019}" // letters + straight/curly apostrophe
    }

    private static func language(of c: Character) -> Language? {
        for s in c.unicodeScalars {
            if (0x0590...0x05FF).contains(s.value) { return .hebrew }
            if (0x41...0x5A).contains(s.value) || (0x61...0x7A).contains(s.value) { return .english }
        }
        return nil
    }

    // MARK: - Accessibility read

    /// A small window of text around the caret plus the caret's index within it.
    /// Uses the parameterized "string for range" attribute so we don't pull an
    /// entire document; falls back to the full value if that's unsupported.
    private static func caretWindow() -> (String, Int)? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef else { return nil }
        var sel = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &sel) else { return nil }
        let caret = sel.location

        let start = max(0, caret - 24)
        var window = CFRange(location: start, length: 48)
        if let axRange = AXValueCreate(.cfRange, &window) {
            var subRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &subRef) == .success,
               let sub = subRef as? String, !sub.isEmpty {
                return (sub, caret - start)
            }
        }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String {
            return (text, caret)
        }
        return nil
    }
}
