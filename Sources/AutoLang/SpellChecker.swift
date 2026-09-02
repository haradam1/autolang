import AppKit

/// Word-validity oracle backed by the system spell checker (which ships with
/// English + Hebrew on macOS), hardened with a Hebrew orthography rule the
/// built-in checker is too lenient to enforce.
final class SpellChecker {
    private let checker = NSSpellChecker.shared
    private let enLang: String?
    private let heLang: String?

    /// Hebrew final-form letters — legal only as the last letter of a word.
    /// Their appearance mid-word means the "word" is layout gibberish.
    private static let finals: Set<Character> = ["ך", "ם", "ן", "ף", "ץ"]

    init() {
        let avail = NSSpellChecker.shared.availableLanguages
        enLang = avail.contains("en") ? "en" : avail.first { $0.hasPrefix("en") }
        heLang = avail.contains("he") ? "he" : avail.first { $0.hasPrefix("he") }
        warmUp()
    }

    /// Force the lazy per-language dictionaries to load now. The first Hebrew
    /// query in a cold process can otherwise return a wrong result, which would
    /// make the first auto-conversion after launch misfire.
    private func warmUp() {
        _ = isValid("test", .english)
        _ = isValid("שלום", .hebrew)
    }

    var hebrewAvailable: Bool { heLang != nil }

    /// Is `word` a real word in `lang`? Must be called on the main thread.
    func isValid(_ word: String, _ lang: Language) -> Bool {
        guard !word.isEmpty else { return false }

        if lang == .hebrew, !hebrewOrthographyValid(word) {
            return false // impossible spelling — don't trust the lenient checker
        }

        if dictionaryValid(word, lang) { return true }

        // Tolerate elided apostrophes in English contractions: someone who types
        // "dont" / "im" / "youre" means a real word, so we must NOT treat it as
        // gibberish and flip it to Hebrew. If inserting an apostrophe anywhere
        // yields a real word, it's valid English.
        if lang == .english, hasContractionForm(word) { return true }

        return false
    }

    private func dictionaryValid(_ word: String, _ lang: Language) -> Bool {
        guard let code = (lang == .hebrew) ? heLang : enLang else { return false }
        let range = checker.checkSpelling(
            of: word, startingAt: 0, language: code,
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound // NSNotFound == nothing misspelled
    }

    /// True if some single-apostrophe insertion makes `word` a real English word.
    private func hasContractionForm(_ word: String) -> Bool {
        let chars = Array(word)
        guard chars.count >= 2, chars.count <= 20, chars.allSatisfy({ $0.isLetter }) else {
            return false
        }
        for i in 1..<chars.count {
            var candidate = chars
            candidate.insert("'", at: i)
            if dictionaryValid(String(candidate), .english) { return true }
        }
        return false
    }

    /// A final-form letter anywhere but the last position invalidates the word.
    private func hebrewOrthographyValid(_ word: String) -> Bool {
        let chars = Array(word)
        for (i, c) in chars.enumerated() where Self.finals.contains(c) {
            if i != chars.count - 1 { return false }
        }
        return true
    }

    // MARK: - Typo correction (Phase 2.5)

    /// The apostrophe form of an English contraction typed without it, e.g.
    /// "dont" -> "don't", or nil if there isn't one.
    func contractionCorrection(_ word: String) -> String? {
        let chars = Array(word)
        guard chars.count >= 2, chars.count <= 20, chars.allSatisfy({ $0.isLetter }) else { return nil }
        guard !dictionaryValid(word, .english) else { return nil }
        for i in 1..<chars.count {
            var candidate = chars
            candidate.insert("'", at: i)
            let s = String(candidate)
            if dictionaryValid(s, .english) { return s }
        }
        return nil
    }

    /// The best spelling correction for a misspelled word, or nil if the word is
    /// already valid or no close correction exists. Conservative: only accepts a
    /// guess within edit distance 2 so we never wildly rewrite a word.
    func topCorrection(_ word: String, _ lang: Language) -> String? {
        guard let code = (lang == .hebrew) ? heLang : enLang else { return nil }
        if lang == .hebrew, !hebrewOrthographyValid(word) { return nil } // don't "fix" gibberish
        guard !dictionaryValid(word, lang) else { return nil }

        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = checker.guesses(forWordRange: range, in: word, language: code,
                                      inSpellDocumentWithTag: 0) ?? []
        guard let best = guesses.first, editDistance(word, best) <= 2 else { return nil }
        return best
    }

    /// Classic Levenshtein distance (small words, so the simple DP is fine).
    private func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}
