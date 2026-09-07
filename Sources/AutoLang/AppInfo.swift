import Foundation

/// Single source of truth for the app version. Keep in sync with
/// Resources/Info.plist (CFBundleShortVersionString).
enum AppInfo {
    static let name = "AutoLang"
    static let version = "0.9.1"
    static var titled: String { "\(name) \(version)" }
}
