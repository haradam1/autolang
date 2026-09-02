import Foundation

/// Ties the pieces together: given a word (keycodes), decide/perform conversion,
/// re-render the on-screen text, and switch the active input source.
final class Engine {
    private let inputSources = InputSourceManager()
    private let injector = TextInjector()
    private let spell = SpellChecker()
    private let appGuard = AppGuard()

    private static let spaceKeycode: Int64 = 0x31

    /// Language momentum: the language of the run we're in. This is the
    /// multi-word context — a single ambiguous word is decided in favor of the
    /// language you've clearly been writing, not judged in isolation.
    private var momentum: Language?

    /// Records the last auto-conversion so the next backspace can undo it.
    private struct LastConversion {
        let original: String   // what the user actually typed (as-typed render)
        let corrected: String  // what we replaced it with
        let from: Language     // original language
        let to: Language       // language we switched to
    }
    private var last: LastConversion?

    // MARK: - Manual

    /// Manual convert: unconditionally flip the current word to the other
    /// language (the user asked for it, so we trust them over the heuristic).
    func manualConvert(word keycodes: [Int64]) {
        guard !keycodes.isEmpty, !Settings.shared.paused else { return }
        let from = inputSources.currentLanguage()
        let to = from.other
        let corrected = KeyMap.render(keycodes, as: to)
        guard !corrected.isEmpty else { return }

        injector.replace(deleting: keycodes.count, with: corrected)
        inputSources.select(to)
        momentum = to // a deliberate switch sets the run's language
        last = nil    // manual is explicit; no auto-undo arming
    }

    // MARK: - Automatic

    /// Called at each word boundary. Returns true if it auto-converted (so the
    /// caller can arm undo + refresh the language badge).
    ///
    /// Precision-first: convert only when the word as-typed is NOT a real word
    /// in the active language but IS a real word in the other. Ambiguous cases
    /// (valid both ways, or gibberish both ways) are left alone.
    func autoConsider(word keycodes: [Int64], boundary: Int64) -> Bool {
        guard Settings.shared.autoConvert, !Settings.shared.paused else { return false }
        guard boundary == Self.spaceKeycode else { return false } // never touch Return/Tab
        guard keycodes.count >= 2 else { return false }           // 1-letter words too noisy
        guard !appGuard.autoConvertBlocked() else { return false } // secure field / excluded app

        let from = inputSources.currentLanguage()
        let to = from.other
        let asTyped = KeyMap.render(keycodes, as: from)
        let other = KeyMap.render(keycodes, as: to)
        guard !asTyped.isEmpty, !other.isEmpty else { return false }

        let validAsTyped = spell.isValid(asTyped, from)
        let validOther = spell.isValid(other, to)

        let shouldConvert: Bool
        if !validAsTyped, validOther {
            shouldConvert = true                 // clear gibberish in the active layout
        } else if validAsTyped, validOther {
            // Ambiguous — a real word both ways. Convert only if momentum says
            // you've been writing the OTHER language (you likely forgot to switch).
            shouldConvert = (momentum == to)
        } else {
            shouldConvert = false                // valid as-typed, or gibberish both ways
        }

        // Update momentum from what we learned (leave it unchanged on the
        // both-invalid case — that's usually a name or typo, no signal).
        if shouldConvert { momentum = to }
        else if validAsTyped { momentum = from }

        guard shouldConvert else { return false }

        // On screen right now: "asTyped " (word + the space). Replace both,
        // re-emitting the space so the user's flow is preserved.
        injector.replace(deleting: keycodes.count + 1, with: other + " ")
        inputSources.select(to)
        last = LastConversion(original: asTyped, corrected: other, from: from, to: to)
        return true
    }

    /// Undo the most recent auto-conversion (user hit backspace right after).
    func revert() {
        guard let l = last else { return }
        last = nil
        // On screen: "corrected " — restore "original " and switch back.
        injector.replace(deleting: l.corrected.count + 1, with: l.original + " ")
        inputSources.select(l.from)
        momentum = l.from // you rejected the switch — the run is the original language
    }
}
