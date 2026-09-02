import Foundation

/// Toggleable behavior. Phase 1 wires the toggles into the menu; the auto/typo
/// features they gate arrive in Phase 2 / 2.5. Persisted via UserDefaults.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let autoConvert = "autoConvert"
        static let typoEN = "typoCorrectEN"
        static let typoHE = "typoCorrectHE"
        static let paused = "paused"
    }

    /// Automatic layout detection + conversion on word boundary (Phase 2).
    var autoConvert: Bool {
        get { defaults.bool(forKey: Key.autoConvert) }
        set { defaults.set(newValue, forKey: Key.autoConvert) }
    }

    /// English typo correction (Phase 2.5).
    var typoCorrectEN: Bool {
        get { defaults.bool(forKey: Key.typoEN) }
        set { defaults.set(newValue, forKey: Key.typoEN) }
    }

    /// Hebrew typo correction (Phase 2.5, conservative, off by default).
    var typoCorrectHE: Bool {
        get { defaults.bool(forKey: Key.typoHE) }
        set { defaults.set(newValue, forKey: Key.typoHE) }
    }

    /// Global pause — the tap stays installed but conversions are suppressed.
    var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }
}
