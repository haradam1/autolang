import AppKit
import Carbon

/// Decides where auto-conversion must stay out of the way: password fields and
/// apps where wrong-layout "gibberish" is usually intentional (terminals, code
/// editors, password managers). Manual convert (⌃⌥H) ignores these — it's an
/// explicit user request.
final class AppGuard {
    /// Bundle IDs where auto-convert is disabled by default. Phase 3 turns this
    /// into a user-editable per-app allow/deny list.
    private static let excluded: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.sublimetext.4",
        "com.1password.1password",
        "com.apple.keychainaccess"
    ]

    /// True when auto-conversion should be suppressed right now.
    func autoConvertBlocked() -> Bool {
        // A password / secure-input field is focused anywhere on the system.
        if IsSecureEventInputEnabled() { return true }

        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Self.excluded.contains(id) {
            return true
        }
        return false
    }
}
