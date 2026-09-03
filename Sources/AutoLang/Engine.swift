import Foundation

/// Decides and performs edits at each word boundary: layout conversion (with a
/// one-word retroactive lookback), language momentum, and typo correction —
/// all expressed as "replace a trailing region of text", so a single undo path
/// covers every kind of edit.
final class Engine {
    private let inputSources = InputSourceManager()
    private let injector = TextInjector()
    private let spell = SpellChecker()
    private let appGuard = AppGuard()

    private static let spaceKeycode: Int64 = 0x31

    /// Language momentum: the language of the run we're in. A single ambiguous
    /// word is decided in favor of the language you've clearly been writing.
    private var momentum: Language?

    /// A held ambiguous word (valid in both languages) whose language we can't
    /// decide yet. If the NEXT word disambiguates the run, we convert this one
    /// retroactively. One-word lookback — this is the "analyze 2 words" behavior.
    private var deferred: (keycodes: [Int64], asTyped: String, from: Language)?

    /// The last text edit we made, for one-press undo. Works for conversions,
    /// retroactive conversions, and typo fixes alike.
    private struct Edit {
        let originalText: String   // what was on screen before (incl. trailing space)
        let correctedText: String  // what we replaced it with (incl. trailing space)
        let restoreLang: Language  // input source to restore on undo
    }
    private var lastEdit: Edit?

    // MARK: - Manual convert (⌃⌥H)

    func manualConvert(word keycodes: [Int64]) {
        guard !keycodes.isEmpty, !Settings.shared.paused else { return }
        let from = inputSources.currentLanguage()
        let to = from.other
        let corrected = KeyMap.render(keycodes, as: to)
        guard !corrected.isEmpty else { return }

        injector.replace(deleting: keycodes.count, with: corrected)
        inputSources.select(to)
        momentum = to
        deferred = nil
        lastEdit = nil // manual is explicit; not part of the auto-undo flow
    }

    // MARK: - Context reset (backspace, cursor moves we can observe)

    /// Called when the user edits in a way that breaks our on-screen position
    /// assumptions (e.g. backspace). Drops the retroactive lookback so we never
    /// delete the wrong span.
    func resetContext() { deferred = nil }

    // MARK: - Word boundary

    /// Process a just-completed word. Returns true if we changed the text (so the
    /// caller arms undo + refreshes the badge).
    func processWord(_ keycodes: [Int64], boundary: Int64) -> Bool {
        guard !Settings.shared.paused else { return false }
        // Only space-terminated words are safe to rewrite; Return/Tab end a run.
        if boundary != Self.spaceKeycode { deferred = nil; return false }
        guard keycodes.count >= 2 else { deferred = nil; return false }
        guard !appGuard.autoConvertBlocked() else { deferred = nil; return false }

        let from = inputSources.currentLanguage()
        let to = from.other
        let asTyped = KeyMap.render(keycodes, as: from)
        let other = KeyMap.render(keycodes, as: to)
        guard !asTyped.isEmpty, !other.isEmpty else { deferred = nil; return false }

        let validSelf = spell.isValid(asTyped, from)
        let validOther = spell.isValid(other, to)

        // --- Layout conversion (if enabled) ---
        if Settings.shared.autoConvert {
            if !validSelf, validOther {
                return convert(keycodes: keycodes, asTyped: asTyped, other: other, from: from, to: to)
            } else if validSelf, validOther {
                switch momentum {
                case to:   // run is already the other language — flip this one too
                    return convert(keycodes: keycodes, asTyped: asTyped, other: other, from: from, to: to)
                case from: // consistent with the run — keep, then consider a typo fix
                    deferred = nil
                case nil:  // truly ambiguous, no run yet — hold for the next word
                    deferred = (keycodes, asTyped, from)
                    return false
                default:
                    deferred = nil
                }
            } else if validSelf, !validOther {
                momentum = from; deferred = nil // definitely this language
            } else {
                deferred = nil // gibberish both ways (name?) — leave for typo maybe
            }
        }

        // --- Typo correction (if enabled for this language) ---
        if typoEnabled(from), let fixed = correction(for: asTyped, lang: from), fixed != asTyped {
            return applyEdit(original: asTyped + " ", corrected: fixed + " ",
                             newLang: from, restore: from)
        }
        return false
    }

    /// Undo the most recent auto-edit (user hit backspace right after).
    func revert() {
        guard let e = lastEdit else { return }
        lastEdit = nil
        injector.replace(deleting: e.correctedText.count, with: e.originalText)
        inputSources.select(e.restoreLang)
        momentum = e.restoreLang
        deferred = nil
    }

    // MARK: - Internals

    /// Convert `keycodes` from→to, folding in the deferred previous word when the
    /// run just disambiguated (retroactive one-word lookback).
    private func convert(keycodes: [Int64], asTyped: String, other: String,
                         from: Language, to: Language) -> Bool {
        // Fold in the deferred previous word only if it belongs to the same
        // layout and renders to a real word in the target language.
        var deferredAsTyped: String?
        var deferredOther: String?
        if let d = deferred, d.from == from {
            let dOther = KeyMap.render(d.keycodes, as: to)
            if spell.isValid(dOther, to) {
                deferredAsTyped = d.asTyped
                deferredOther = dOther
            }
        }

        let plan = Engine.planConvert(currentAsTyped: asTyped, currentOther: other,
                                      deferredAsTyped: deferredAsTyped, deferredOther: deferredOther)
        deferred = nil
        momentum = to
        return applyEdit(original: plan.original, corrected: plan.corrected, newLang: to, restore: from)
    }

    /// Pure: assembles the text spans a conversion replaces, folding in a
    /// deferred previous word when present. When a deferred word is folded, the
    /// replacement covers BOTH words — not just the current one. Exposed for test.
    static func planConvert(currentAsTyped: String, currentOther: String,
                            deferredAsTyped: String?, deferredOther: String?)
        -> (original: String, corrected: String) {
        var original = currentAsTyped + " "
        var corrected = currentOther + " "
        if let da = deferredAsTyped, let dOther = deferredOther {
            original = da + " " + original      // deferred word + current word
            corrected = dOther + " " + corrected
        }
        return (original, corrected)
    }

    private func applyEdit(original: String, corrected: String,
                           newLang: Language, restore: Language) -> Bool {
        injector.replace(deleting: original.count, with: corrected)
        inputSources.select(newLang)
        lastEdit = Edit(originalText: original, correctedText: corrected, restoreLang: restore)
        return true
    }

    private func typoEnabled(_ lang: Language) -> Bool {
        lang == .hebrew ? Settings.shared.typoCorrectHE : Settings.shared.typoCorrectEN
    }

    /// Best correction for a word in its (already-decided) language: apostrophe
    /// contractions first, then a conservative spelling guess.
    private func correction(for word: String, lang: Language) -> String? {
        if lang == .english, let c = spell.contractionCorrection(word) { return c }
        return spell.topCorrection(word, lang)
    }
}
