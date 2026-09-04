import AppKit

/// Word-validity oracle backed by the system spell checker (English + Hebrew on
/// macOS), hardened with a Hebrew orthography rule and a curated contraction
/// list, plus conservative typo correction.
final class SpellChecker {
    private let checker = NSSpellChecker.shared
    private let enLang: String?
    private let heLang: String?

    /// Hebrew final-form letters — legal only as the last letter of a word.
    private static let finals: Set<Character> = ["ך", "ם", "ן", "ף", "ץ"]

    /// Curated apostrophe-less → apostrophe contractions. A curated list (vs.
    /// brute-force apostrophe insertion) is what keeps us from inventing
    /// apostrophes in ordinary words like "were", "well", "id", "shed".
    private static let contractions: [String: String] = [
        "dont": "don't", "cant": "can't", "wont": "won't", "isnt": "isn't",
        "arent": "aren't", "wasnt": "wasn't", "werent": "weren't",
        "doesnt": "doesn't", "didnt": "didn't", "havent": "haven't",
        "hasnt": "hasn't", "hadnt": "hadn't", "wouldnt": "wouldn't",
        "couldnt": "couldn't", "shouldnt": "shouldn't", "mustnt": "mustn't",
        "neednt": "needn't", "shant": "shan't", "aint": "ain't",
        "im": "i'm", "ive": "i've", "ill": "i'll", "id": "i'd",
        "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd",
        "hes": "he's", "shes": "she's", "its": "it's", "thats": "that's",
        "whats": "what's", "wheres": "where's", "whos": "who's", "hows": "how's",
        "theres": "there's", "heres": "here's", "lets": "let's",
        "theyre": "they're", "theyve": "they've", "theyll": "they'll",
        "theyd": "they'd", "were": "we're", "weve": "we've", "well": "we'll",
        "wed": "we'd", "wholl": "who'll", "wouldve": "would've",
        "couldve": "could've", "shouldve": "should've", "oclock": "o'clock",
        "yall": "y'all", "maam": "ma'am"
    ]
    // Words above whose bare form is ALSO a common word — for these we must NOT
    // auto-insert an apostrophe (too risky), only accept them as valid.
    private static let ambiguousBare: Set<String> = ["its", "were", "well", "id", "wed", "hell", "shell", "cant", "wont", "lets"]

    init() {
        let avail = NSSpellChecker.shared.availableLanguages
        enLang = avail.contains("en") ? "en" : avail.first { $0.hasPrefix("en") }
        heLang = avail.contains("he") ? "he" : avail.first { $0.hasPrefix("he") }
        warmUp()
    }

    var hebrewAvailable: Bool { heLang != nil }

    private func warmUp() {
        _ = isValid("test", .english)
        _ = isValid("שלום", .hebrew)
    }

    // MARK: - Validity

    /// Is `word` a real word in `lang`? Must be called on the main thread.
    func isValid(_ word: String, _ lang: Language) -> Bool {
        guard !word.isEmpty else { return false }
        if lang == .hebrew, !hebrewOrthographyValid(word) { return false }
        if dictionaryValid(word, lang) { return true }
        // A known contraction typed without its apostrophe is still a real word,
        // so we must not mistake it for gibberish and flip it to Hebrew.
        if lang == .english, Self.contractions[word.lowercased()] != nil { return true }
        return false
    }

    private func dictionaryValid(_ word: String, _ lang: Language) -> Bool {
        guard let code = (lang == .hebrew) ? heLang : enLang else { return false }
        let range = checker.checkSpelling(
            of: word, startingAt: 0, language: code,
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }

    private func hebrewOrthographyValid(_ word: String) -> Bool {
        let chars = Array(word)
        for (i, c) in chars.enumerated() where Self.finals.contains(c) {
            if i != chars.count - 1 { return false }
        }
        return true
    }

    // MARK: - Typo correction (Phase 2.5)

    /// The apostrophe form of a contraction typed without it (e.g. "dont" ->
    /// "don't"), case-matched to the input. Returns nil when there's no *safe*
    /// contraction — words whose bare form is itself common are left alone.
    func contractionCorrection(_ word: String) -> String? {
        let lower = word.lowercased()
        guard !Self.ambiguousBare.contains(lower), let form = Self.contractions[lower] else { return nil }
        return applyCase(of: word, to: form)
    }

    /// A HIGH-PRECISION spelling correction, or nil. Only two safe typo classes
    /// are auto-applied — a repeated-letter run collapsing to a real word
    /// ("helllo"->"hello") and an adjacent transposition ("teh"->"the",
    /// "recieve"->"receive"). Riskier edits (substitutions, arbitrary deletions)
    /// are declined so names like "yaron" are never mangled into "yarn". Case
    /// of the input is preserved.
    func topCorrection(_ word: String, _ lang: Language) -> String? {
        guard let code = (lang == .hebrew) ? heLang : enLang else { return nil }
        if lang == .hebrew, !hebrewOrthographyValid(word) { return nil }
        guard !dictionaryValid(word, lang) else { return nil }

        let lower = word.lowercased()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = checker.guesses(forWordRange: range, in: word, language: code,
                                      inSpellDocumentWithTag: 0) ?? []
        for guess in guesses where isSafeTypo(from: lower, to: guess.lowercased()) {
            return applyCase(of: word, to: guess)
        }
        return nil
    }

    /// True only for the two safe typo classes above.
    private func isSafeTypo(from word: String, to guess: String) -> Bool {
        guard word != guess else { return false }
        return collapsesRepeatedLetter(word, to: guess) || isAdjacentTransposition(word, guess)
    }

    /// `guess` == `word` with one letter removed from a run of identical letters.
    private func collapsesRepeatedLetter(_ word: String, to guess: String) -> Bool {
        let w = Array(word)
        guard w.count == guess.count + 1 else { return false }
        for i in 0..<w.count {
            let repeatsNeighbor = (i > 0 && w[i] == w[i - 1]) || (i < w.count - 1 && w[i] == w[i + 1])
            guard repeatsNeighbor else { continue }
            var candidate = w; candidate.remove(at: i)
            if String(candidate) == guess { return true }
        }
        return false
    }

    /// `guess` == `word` with one adjacent pair swapped.
    private func isAdjacentTransposition(_ word: String, _ guess: String) -> Bool {
        let w = Array(word)
        guard w.count == guess.count, w.count >= 2 else { return false }
        for i in 0..<(w.count - 1) {
            var candidate = w
            candidate.swapAt(i, i + 1)
            if String(candidate) == guess { return true }
        }
        return false
    }

    /// Reapply `source`'s capitalization pattern to `replacement`:
    /// ALLCAPS -> ALLCAPS, Titlecase -> Titlecase, otherwise lowercase.
    private func applyCase(of source: String, to replacement: String) -> String {
        if source.count > 1, source == source.uppercased(), source != source.lowercased() {
            return replacement.uppercased()
        }
        if let first = source.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
