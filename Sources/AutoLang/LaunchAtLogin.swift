import ServiceManagement
import Foundation

/// Start-on-boot via the modern SMAppService login-item API (macOS 13+).
/// Registers the app bundle as a login item so it launches hidden into the
/// menu bar at sign-in.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Failures are logged (e.g. running a loose binary
    /// rather than the .app bundle).
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSLog("AutoLang: launch-at-login \(on ? "register" : "unregister") failed: \(error)")
            return false
        }
    }
}
