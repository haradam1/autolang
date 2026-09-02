import Foundation

/// Accumulates the keycodes of the word currently being typed.
///
/// Phase 1 only needs "the word in progress" so the manual-convert hotkey can
/// re-render it. Phase 2 grows this into the sliding multi-word window that the
/// language state machine reasons over (momentum + deferred/retroactive convert).
final class WordBuffer {
    /// Keycodes of the in-progress word, in type order. Only mappable keys are
    /// stored, so `count` == number of visible characters we'd need to delete.
    private(set) var current: [Int64] = []

    /// The last completed word (flushed at a boundary). Kept for a future
    /// "convert the word I just finished" path; unused in the Phase 1 flow.
    private(set) var previous: [Int64] = []

    var isEmpty: Bool { current.isEmpty }
    var length: Int { current.count }

    func append(keycode: Int64) {
        if KeyMap.isMappable(keycode) {
            current.append(keycode)
        } else {
            // A non-mappable key mid-word (e.g. a digit) breaks the run so we
            // don't mis-transliterate. Conservative for the skeleton.
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
