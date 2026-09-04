import Foundation

/// Decides and performs edits at each word boundary: layout conversion with a
/// multi-word deferred run (so short/ambiguous words are judged in phrase
/// context), language momentum, typo correction, capitalization preservation,
/// and a personal dictionary that learns from your undos.
final class Engine {
    private let inputSources = InputSourceManager()
    private let injector = TextInjector()
    private let spell = SpellChecker()
    private let appGuard = AppGuard()
    private let dictionary = UserDictionary()

    private static let spaceKeycode: Int64 = 0x31
    private static let maxPending = 8 // bound the retroactive span

    /// The language of the run we're in. A single ambiguous word follows the
    /// language you've clearly been writing rather than being judged alone.
    private var momentum: Language?

    /// Held ambiguous words (valid in both languages) with no run established
    /// yet — a contiguous trailing run. When a later word disambiguates, the
    /// whole run is converted retroactively. This is the multi-word context.
    private struct Pending { let keystrokes: [Keystroke]; let asTyped: String; let from: Language }
    private var pending: [Pending] = []

    /// The last text edit, for one-press undo (and to learn from it).
    private struct Edit {
        let originalText: String
        let correctedText: String
        let restoreLang: Language
        let sourceWords: [String] // as-typed words this edit touched
    }
    private var lastEdit: Edit?

    // Menu surface for the personal dictionary.
    var learnedCount: Int { dictionary.count }
    func learnedWords() -> [String] { dictionary.allWords() }
    func removeLearned(_ word: String) { dictionary.remove(word) }
    func forgetLearned() { dictionary.forgetAll() }

    // MARK: - Manual convert (⌃⌥H)

    func manualConvert(word keystrokes: [Keystroke]) {
        guard !keystrokes.isEmpty, !Settings.shared.paused else { return }
        let from = inputSources.currentLanguage()
        let to = from.other
        let corrected = KeyMap.render(keystrokes, as: to)
        guard !corrected.isEmpty else { return }

        injector.replace(deleting: keystrokes.count, with: corrected)
        inputSources.select(to)
        momentum = to
        pending.removeAll()
        lastEdit = nil
        Stats.shared.recordConversion(words: [corrected], to: to, manual: true)
    }

    /// Backspace / cursor move: drop the retroactive run so we never rewrite the
    /// wrong span.
    func resetContext() { pending.removeAll() }

    // MARK: - Word boundary

    func processWord(_ keystrokes: [Keystroke], boundary: Int64) -> Bool {
        guard !Settings.shared.paused else { return false }
        if boundary != Self.spaceKeycode { pending.removeAll(); return false }
        guard keystrokes.count >= 2 else { pending.removeAll(); return false }
        guard !appGuard.autoConvertBlocked() else { pending.removeAll(); return false }

        let from = inputSources.currentLanguage()
        let to = from.other
        let asTyped = KeyMap.render(keystrokes, as: from)
        let other = KeyMap.render(keystrokes, as: to)
        guard !asTyped.isEmpty, !other.isEmpty else { pending.removeAll(); return false }

        // Personal dictionary: never touch a word you've protected.
        if dictionary.isProtected(asTyped) { pending.removeAll(); momentum = from; return false }

        let validSelf = spell.isValid(asTyped, from)
        let validOther = spell.isValid(other, to)

        if Settings.shared.autoConvert {
            if !validSelf, validOther {
                return convertRun(asTyped: asTyped, other: other, from: from, to: to)
            } else if validSelf, validOther {
                if momentum == to {
                    return convertRun(asTyped: asTyped, other: other, from: from, to: to)
                } else if momentum == from {
                    pending.removeAll()            // consistent with the run — keep
                } else {
                    defer_(keystrokes, asTyped, from) // ambiguous, no run yet — hold
                    return false
                }
            } else if validSelf, !validOther {
                momentum = from; pending.removeAll() // definitely this language
            } else {
                pending.removeAll()                  // gibberish both ways — leave for typo
            }
        } else {
            pending.removeAll()
        }

        // Typo correction on the committed current word (if enabled & not protected).
        if typoEnabled(from), let fixed = correction(for: asTyped, lang: from), fixed != asTyped {
            Stats.shared.recordTypo(word: fixed)
            return applyEdit(asTyped: [asTyped], corrected: [fixed], newLang: from, restore: from)
        }
        return false
    }

    /// Undo the most recent auto-edit, and LEARN from it: the reverted words are
    /// protected so we won't convert/correct them again.
    func revert() {
        guard let e = lastEdit else { return }
        lastEdit = nil
        injector.replace(deleting: e.correctedText.count, with: e.originalText)
        inputSources.select(e.restoreLang)
        momentum = e.restoreLang
        pending.removeAll()
        for w in e.sourceWords { dictionary.protect(w) }
        Stats.shared.recordUndo()
    }

    // MARK: - Internals

    /// Convert the current word, folding in the contiguous suffix of the pending
    /// run whose target-language render is valid (so the whole phrase flips).
    private func convertRun(asTyped: String, other: String, from: Language, to: Language) -> Bool {
        var foldAsTyped: [String] = []
        var foldCorrected: [String] = []
        for p in pending.reversed() {
            guard p.from == from else { break }
            let pOther = KeyMap.render(p.keystrokes, as: to)
            if spell.isValid(pOther, to) {
                foldAsTyped.insert(p.asTyped, at: 0)
                foldCorrected.insert(pOther, at: 0)
            } else { break }
        }
        pending.removeAll()
        momentum = to
        let correctedWords = foldCorrected + [other]
        Stats.shared.recordConversion(words: correctedWords, to: to)
        return applyEdit(asTyped: foldAsTyped + [asTyped],
                         corrected: correctedWords,
                         newLang: to, restore: from)
    }

    private func defer_(_ keystrokes: [Keystroke], _ asTyped: String, _ from: Language) {
        if pending.count >= Self.maxPending { pending.removeAll() } // cap the span
        pending.append(Pending(keystrokes: keystrokes, asTyped: asTyped, from: from))
    }

    private func applyEdit(asTyped: [String], corrected: [String],
                           newLang: Language, restore: Language) -> Bool {
        let plan = Engine.planConvert(asTyped: asTyped, corrected: corrected)
        injector.replace(deleting: plan.original.count, with: plan.corrected)
        inputSources.select(newLang)
        lastEdit = Edit(originalText: plan.original, correctedText: plan.corrected,
                        restoreLang: restore, sourceWords: asTyped)
        return true
    }

    /// Pure: assembles the (original, corrected) text spans for an edit covering
    /// one or more consecutive words. Exposed for testing.
    static func planConvert(asTyped: [String], corrected: [String])
        -> (original: String, corrected: String) {
        (asTyped.joined(separator: " ") + " ", corrected.joined(separator: " ") + " ")
    }

    private func typoEnabled(_ lang: Language) -> Bool {
        lang == .hebrew ? Settings.shared.typoCorrectHE : Settings.shared.typoCorrectEN
    }

    private func correction(for word: String, lang: Language) -> String? {
        if lang == .english, let c = spell.contractionCorrection(word) { return c }
        return spell.topCorrection(word, lang)
    }
}
