import Foundation

/// Personal preference dictionary: words AutoLang should leave alone (never
/// auto-convert, never typo-correct). It learns automatically — undoing a
/// conversion protects that word so it won't be touched again — and can be
/// managed from the menu. Persisted in UserDefaults.
final class UserDictionary {
    private let defaults = UserDefaults.standard
    private let key = "protectedWords"
    private var words: Set<String>

    init() {
        words = Set(defaults.stringArray(forKey: key) ?? [])
    }

    var count: Int { words.count }

    /// Case-insensitive membership.
    func isProtected(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    /// Learn a word (idempotent). Ignores empties/whitespace.
    func protect(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespaces).lowercased()
        guard !w.isEmpty else { return }
        if words.insert(w).inserted { persist() }
    }

    func forgetAll() {
        words.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(Array(words), forKey: key)
    }
}
