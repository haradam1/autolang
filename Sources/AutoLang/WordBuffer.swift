import Foundation

/// Accumulates the keystrokes of the word currently being typed (keycode +
/// shift state, so capitalization survives a conversion).
final class WordBuffer {
    private(set) var current: [Keystroke] = []
    private(set) var previous: [Keystroke] = []

    var isEmpty: Bool { current.isEmpty }
    var length: Int { current.count }

    func append(_ keystroke: Keystroke) {
        if KeyMap.isMappable(keystroke.code) {
            current.append(keystroke)
        } else {
            // A non-mappable key mid-word (e.g. a digit) breaks the run so we
            // don't mis-transliterate.
            flush()
        }
    }

    /// Called on backspace: drop the last keystroke.
    func deleteLast() {
        if !current.isEmpty { current.removeLast() }
    }

    /// Called at a word boundary: move current -> previous, reset current.
    func flush() {
        if !current.isEmpty { previous = current }
        current = []
    }

    func clear() {
        current = []
    }
}
