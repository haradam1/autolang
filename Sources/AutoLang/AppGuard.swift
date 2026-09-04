import AppKit
import Carbon

/// Decides where auto-conversion must stay out of the way: password fields and
/// apps where wrong-layout "gibberish" is usually intentional (terminals, code
/// editors, password managers). Manual convert (⌃⌥H) ignores these — it's an
/// explicit user request.
final class AppGuard {
    /// True when auto-conversion should be suppressed right now.
    func autoConvertBlocked() -> Bool {
        // A password / secure-input field is focused anywhere on the system.
        if IsSecureEventInputEnabled() { return true }

        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           AppRules.shared.isExcluded(id) {
            return true
        }
        return false
    }
}
