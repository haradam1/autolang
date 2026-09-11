import AppKit
import ApplicationServices
import Carbon

/// Menu-bar app controller: owns the status item, permission onboarding, the
/// event tap, and the engine that performs conversions.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Created in applicationDidFinishLaunching — creating it during init (before
    // app.run() / the activation policy is set) can leave it off the menu bar.
    private var statusItem: NSStatusItem!
    private let tapController = EventTapController()
    private let engine = Engine()
    private let inputSources = InputSourceManager()

    private var tapRunning = false
    private var permissionTimer: Timer?
    private var flashTimer: Timer?

    /// The last non-AutoLang app you were in, so the per-app menu can target it.
    private var lastActiveApp: (name: String, id: String)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon (LSUIElement behavior)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NSLog("AutoLang: status item created, button=\(statusItem.button != nil)")

        buildMenu()
        refreshBadge()

        // Track layout changes so the menu-bar badge always shows the live language.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        // Remember the app you were typing in (for the per-app menu).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if Settings.shared.debugLogging {
            DebugLog.shared.begin("AutoLang \(AppInfo.version) — launched")
        }
        wireEngine()
        startTapIfPermitted()
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        lastActiveApp = (name: app.localizedName ?? id, id: id)
    }

    // MARK: - Permissions

    private func startTapIfPermitted() {
        // Prompt if we're not trusted yet (harmless no-op if we already are).
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        tryStartTap()
        // Always watch: arms the tap the moment trust appears, AND re-arms if a
        // rebuild's new code identity invalidated a prior grant (you re-grant,
        // the icon flips from ⚠️ to 💬 live — no relaunch needed).
        startPermissionWatch()
        buildMenu()
        refreshBadge()
    }

    private func tryStartTap() {
        guard !tapRunning, AXIsProcessTrusted() else { return }
        tapRunning = tapController.start()
    }

    private func startPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let was = self.tapRunning
            self.tryStartTap()
            if self.tapRunning != was {         // state changed -> refresh UI
                self.buildMenu()
                self.refreshBadge()
            }
            if self.tapRunning { timer.invalidate() } // armed; stop polling
        }
    }

    // MARK: - Engine wiring

    private func wireEngine() {
        tapController.onManualConvert = { [weak self] word in
            self?.engine.manualConvert(word: word)
            self?.tapController.resetCurrentWord()
            self?.refreshBadge()
            self?.flash()
        }
        tapController.onWordBoundary = { [weak self] word, boundary, editing in
            guard let self else { return }
            if self.engine.processWord(word, boundary: boundary, editingExisting: editing) {
                self.tapController.armUndo()   // next backspace undoes it
                self.refreshBadge()            // language may have flipped
                self.flash()
            }
        }
        tapController.onUndo = { [weak self] in
            self?.engine.revert()
            self?.refreshBadge()
        }
        tapController.onContextReset = { [weak self] in
            self?.engine.resetContext()
        }
        tapController.onClipboardConvert = { [weak self] in
            let changed = ClipboardConverter.convertPasteboard()
            DebugLog.shared.log("CLIPBOARD convert changed=\(changed)")
            if changed { self?.flash() }
        }
        tapController.firstEditKeystroke = { [weak self] keycode, shifted in
            guard let self else { return false }
            let handled = self.engine.correctFirstEditKeystroke(keycode: keycode, shifted: shifted)
            if handled { self.refreshBadge() } // language switched
            return handled
        }
    }

    /// Briefly tint the menu-bar icon to acknowledge a conversion.
    private func flash() {
        guard Settings.shared.flashOnConvert, let button = statusItem?.button else { return }
        flashTimer?.invalidate()
        button.contentTintColor = .controlAccentColor
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak button] _ in
            button?.contentTintColor = nil
        }
    }

    // MARK: - Status item

    private func refreshBadge() {
        guard let button = statusItem.button else { return }
        button.title = "" // the brand image carries everything
        button.imagePosition = .imageOnly
        button.image = tapRunning
            ? MenuBarIcon.image(language: inputSources.currentLanguage(), style: Settings.shared.iconStyle)
            : MenuBarIcon.warning()
    }

    @objc private func inputSourceChanged() {
        DebugLog.shared.log("ACTIVE=\(inputSources.currentLanguage() == .hebrew ? "HE" : "EN") (observed)")
        refreshBadge()
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Version + live status.
        let state = tapRunning ? "active" : "needs Accessibility permission"
        let header = NSMenuItem(title: "\(AppInfo.titled) · \(state)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !tapRunning {
            menu.addItem(withTitle: "Open Accessibility settings…",
                         action: #selector(openAccessibility), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Convert current word  (⌃⌥H)", action: #selector(noopHotkeyHint), keyEquivalent: "")
            .toolTip = "Type a word, then press Control-Option-H"
        let clip = NSMenuItem(title: "Convert clipboard  (⌃⌥V)", action: #selector(convertClipboard), keyEquivalent: "")
        clip.target = self
        clip.toolTip = "Transliterate the clipboard EN⇄HE"
        menu.addItem(clip)

        menu.addItem(.separator())
        addToggle(to: menu, title: "Auto-detect & convert", isOn: Settings.shared.autoConvert,
                  action: #selector(toggleAuto))
        addToggle(to: menu, title: "Fix typos (English)", isOn: Settings.shared.typoCorrectEN,
                  action: #selector(toggleTypoEN))
        addToggle(to: menu, title: "Fix typos (Hebrew)", isOn: Settings.shared.typoCorrectHE,
                  action: #selector(toggleTypoHE))
        addToggle(to: menu, title: "Match language to cursor", isOn: Settings.shared.matchLanguageOnCursor,
                  action: #selector(toggleMatchCursor))
        addToggle(to: menu, title: "Flash on convert", isOn: Settings.shared.flashOnConvert,
                  action: #selector(toggleFlash))
        addToggle(to: menu, title: "Pause", isOn: Settings.shared.paused,
                  action: #selector(togglePause))

        menu.addItem(.separator())
        menu.addItem(dictionarySubmenuItem())
        menu.addItem(statisticsSubmenuItem())
        menu.addItem(perAppSubmenuItem())
        menu.addItem(iconStyleSubmenuItem())

        menu.addItem(.separator())
        menu.addItem(debugSubmenuItem())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(withTitle: "Quit AutoLang", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: - Icon style picker

    private func iconStyleSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Icon style", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for style in IconStyle.allCases {
            let si = NSMenuItem(title: style.title, action: #selector(pickIconStyle(_:)), keyEquivalent: "")
            si.target = self
            si.representedObject = style.rawValue
            si.state = (style == Settings.shared.iconStyle) ? .on : .off
            si.image = MenuBarIcon.image(language: inputSources.currentLanguage(), style: style)
            sub.addItem(si)
        }
        item.submenu = sub
        return item
    }

    // MARK: - Per-app rules

    private func perAppSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Per-app rules", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        if let app = lastActiveApp {
            let on = !AppRules.shared.isExcluded(app.id)
            let toggle = NSMenuItem(title: "Convert in \(app.name)", action: #selector(toggleCurrentApp), keyEquivalent: "")
            toggle.state = on ? .on : .off
            toggle.target = self
            sub.addItem(toggle)
        } else {
            let hint = NSMenuItem(title: "Switch to an app, then reopen this menu", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            sub.addItem(hint)
        }

        let excluded = AppRules.shared.all()
        if !excluded.isEmpty {
            sub.addItem(.separator())
            let head = NSMenuItem(title: "Disabled in (click to re-enable):", action: nil, keyEquivalent: "")
            head.isEnabled = false
            sub.addItem(head)
            for id in excluded {
                let ei = NSMenuItem(title: "✓  \(shortName(id))", action: #selector(reEnableApp(_:)), keyEquivalent: "")
                ei.target = self
                ei.representedObject = id
                ei.toolTip = id
                sub.addItem(ei)
            }
        }
        item.submenu = sub
        return item
    }

    /// Last dotted component of a bundle id, for a friendlier label.
    private func shortName(_ bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    // MARK: - Learned words submenu (browse + delete per word)

    private func dictionarySubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Learned words (\(engine.learnedCount))", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let words = engine.learnedWords()
        if words.isEmpty {
            let empty = NSMenuItem(title: "None yet — undo a conversion to protect a word", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            let hint = NSMenuItem(title: "Click a word to remove it", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            sub.addItem(hint)
            sub.addItem(.separator())
            for w in words {
                let wi = NSMenuItem(title: "✕  \(w)", action: #selector(removeLearnedWord(_:)), keyEquivalent: "")
                wi.target = self
                wi.representedObject = w
                wi.toolTip = "Remove “\(w)” — AutoLang may convert/correct it again"
                sub.addItem(wi)
            }
            sub.addItem(.separator())
            sub.addItem(withTitle: "Forget all", action: #selector(forgetLearned), keyEquivalent: "").target = self
        }
        item.submenu = sub
        return item
    }

    // MARK: - Debug submenu

    private func debugSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let toggle = NSMenuItem(title: "Log everything I type (diagnostic)",
                                action: #selector(toggleDebugLogging), keyEquivalent: "")
        toggle.state = Settings.shared.debugLogging ? .on : .off
        toggle.target = self
        toggle.toolTip = "Records keystrokes, decisions, and language changes to a local file for debugging."
        sub.addItem(toggle)

        if Settings.shared.debugLogging {
            let note = NSMenuItem(title: "Recording to ~/Library/Logs/AutoLang/debug.log", action: nil, keyEquivalent: "")
            note.isEnabled = false
            sub.addItem(note)
        }
        sub.addItem(.separator())
        sub.addItem(withTitle: "Open debug log", action: #selector(openDebugLog), keyEquivalent: "").target = self
        sub.addItem(withTitle: "Reveal log in Finder", action: #selector(revealDebugLog), keyEquivalent: "").target = self
        sub.addItem(withTitle: "Clear debug log", action: #selector(clearDebugLog), keyEquivalent: "").target = self

        item.submenu = sub
        return item
    }

    // MARK: - Statistics submenu

    private func statisticsSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Statistics", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let d = Stats.shared.data

        func info(_ title: String) { let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; sub.addItem(i) }

        info("Total conversions: \(d.total)")
        info("   EN → HE: \(d.enToHe)   HE → EN: \(d.heToEn)")
        info("Typo fixes: \(d.typoFixes)   Manual: \(d.manualConverts)   Undos: \(d.undos)")

        let top = Stats.shared.topWords(limit: 5)
        if !top.isEmpty {
            sub.addItem(.separator())
            info("Top words")
            let maxCount = max(top.first?.count ?? 1, 1)
            for t in top {
                let filled = Int((Double(t.count) / Double(maxCount) * 10).rounded())
                let bar = String(repeating: "▉", count: max(filled, 1)) + String(repeating: "·", count: 10 - max(filled, 1))
                info("  \(bar)  \(t.word) (\(t.count))")
            }
        }

        sub.addItem(.separator())
        sub.addItem(withTitle: "Open detailed stats…", action: #selector(openDetailedStats), keyEquivalent: "").target = self
        sub.addItem(withTitle: "Reset statistics", action: #selector(resetStats), keyEquivalent: "").target = self

        item.submenu = sub
        return item
    }

    private func addToggle(to menu: NSMenu, title: String, isOn: Bool, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = isOn ? .on : .off
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func noopHotkeyHint() {}

    @objc private func forgetLearned() { engine.forgetLearned(); buildMenu() }

    @objc private func removeLearnedWord(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        engine.removeLearned(word)
        buildMenu()
    }

    @objc private func resetStats() { Stats.shared.reset(); buildMenu() }

    @objc private func convertClipboard() {
        _ = ClipboardConverter.convertPasteboard()
    }

    @objc private func pickIconStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = IconStyle(rawValue: raw) else { return }
        Settings.shared.iconStyle = style
        refreshBadge()
        buildMenu()
    }

    @objc private func toggleCurrentApp() {
        guard let app = lastActiveApp else { return }
        let nowExcluded = !AppRules.shared.isExcluded(app.id)
        AppRules.shared.setExcluded(app.id, nowExcluded)
        buildMenu()
    }

    @objc private func reEnableApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppRules.shared.setExcluded(id, false)
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        buildMenu()
    }

    @objc private func openDetailedStats() {
        let html = StatsReport.html(from: Stats.shared.data, top: Stats.shared.topWords(limit: 15))
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoLang", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("stats.html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("AutoLang: failed to write stats report: \(error)")
        }
    }

    @objc private func toggleAuto() { Settings.shared.autoConvert.toggle(); buildMenu() }
    @objc private func toggleTypoEN() { Settings.shared.typoCorrectEN.toggle(); buildMenu() }
    @objc private func toggleTypoHE() { Settings.shared.typoCorrectHE.toggle(); buildMenu() }
    @objc private func togglePause() { Settings.shared.paused.toggle(); buildMenu() }
    @objc private func toggleFlash() { Settings.shared.flashOnConvert.toggle(); buildMenu() }
    @objc private func toggleMatchCursor() { Settings.shared.matchLanguageOnCursor.toggle(); buildMenu() }

    @objc private func toggleDebugLogging() {
        Settings.shared.debugLogging.toggle()
        if Settings.shared.debugLogging {
            DebugLog.shared.begin("AutoLang \(AppInfo.version) — debug session start")
        }
        buildMenu()
    }
    @objc private func openDebugLog() { NSWorkspace.shared.open(DebugLog.shared.fileURL) }
    @objc private func revealDebugLog() { NSWorkspace.shared.activateFileViewerSelecting([DebugLog.shared.fileURL]) }
    @objc private func clearDebugLog() { DebugLog.shared.clear() }
}
