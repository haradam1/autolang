import Foundation

/// Usage statistics, persisted in UserDefaults. Records what AutoLang did so the
/// menu and the detailed dashboard can show a breakdown.
final class Stats {
    static let shared = Stats()
    private let defaults = UserDefaults.standard
    private let key = "statsData"

    struct Data: Codable {
        var enToHe = 0
        var heToEn = 0
        var typoFixes = 0
        var manualConverts = 0
        var undos = 0
        var wordCounts: [String: Int] = [:] // corrected word -> times produced
        var total: Int { enToHe + heToEn }
    }

    private(set) var data: Data

    private init() {
        if let raw = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Data.self, from: raw) {
            data = decoded
        } else {
            data = Data()
        }
    }

    // MARK: - Recording

    /// A layout conversion of one or more words. `words` are the corrected forms.
    func recordConversion(words: [String], to lang: Language, manual: Bool = false) {
        for w in words {
            if lang == .hebrew { data.enToHe += 1 } else { data.heToEn += 1 }
            bump(w)
        }
        if manual { data.manualConverts += 1 }
        save()
    }

    func recordTypo(word: String) {
        data.typoFixes += 1
        bump(word)
        save()
    }

    func recordUndo() {
        data.undos += 1
        save()
    }

    func reset() {
        data = Data()
        save()
    }

    /// Words most produced, highest first.
    func topWords(limit: Int) -> [(word: String, count: Int)] {
        data.wordCounts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(limit).map { (word: $0.key, count: $0.value) }
    }

    private func bump(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        data.wordCounts[w, default: 0] += 1
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            defaults.set(raw, forKey: key)
        }
    }
}
