import Foundation

/// User-editable per-app exclusions: apps where auto-convert is disabled
/// (terminals, editors, password managers by default, but fully editable).
/// Persisted in UserDefaults.
final class AppRules {
    static let shared = AppRules()
    private let defaults = UserDefaults.standard
    private let key = "excludedApps"
    private var excluded: Set<String>

    private static let seed: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.jetbrains.intellij",
        "com.jetbrains.pycharm", "com.sublimetext.4",
        "com.1password.1password", "com.apple.keychainaccess"
    ]

    private init() {
        if let saved = defaults.array(forKey: key) as? [String] {
            excluded = Set(saved)
        } else {
            excluded = Set(Self.seed) // sensible defaults on first run
            persist()
        }
    }

    func isExcluded(_ bundleID: String) -> Bool { excluded.contains(bundleID) }

    func setExcluded(_ bundleID: String, _ on: Bool) {
        if on { excluded.insert(bundleID) } else { excluded.remove(bundleID) }
        persist()
    }

    func all() -> [String] { excluded.sorted() }

    private func persist() { defaults.set(Array(excluded), forKey: key) }
}
