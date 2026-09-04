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

        wireEngine()
        startTapIfPermitted()
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
        }
        tapController.onWordBoundary = { [weak self] word, boundary in
            guard let self else { return }
            if self.engine.processWord(word, boundary: boundary) {
                self.tapController.armUndo()   // next backspace undoes it
                self.refreshBadge()            // language may have flipped
            }
        }
        tapController.onUndo = { [weak self] in
            self?.engine.revert()
            self?.refreshBadge()
        }
        tapController.onContextReset = { [weak self] in
            self?.engine.resetContext()
        }
    }

    // MARK: - Status item

    private func refreshBadge() {
        guard let button = statusItem.button else { return }
        let lang = inputSources.currentLanguage()

        // A real menu-bar glyph so presence is obvious at a glance:
        //  • active  -> speech-bubble with a character (we're watching input)
        //  • blocked -> warning triangle (needs Accessibility)
        let symbol = tapRunning ? "character.bubble.fill" : "exclamationmark.triangle.fill"
        let describe = tapRunning ? "AutoLang active" : "AutoLang needs Accessibility permission"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: describe)
        image?.isTemplate = true // adapts to light/dark menu bar

        button.image = image
        button.imagePosition = .imageLeading
        button.title = " \(lang.badge)" // e.g. " EN" / " עב"
    }

    @objc private func inputSourceChanged() { refreshBadge() }

    private func buildMenu() {
        let menu = NSMenu()

        let status = tapRunning ? "AutoLang: active" : "AutoLang: needs Accessibility permission"
        let statusItemEntry = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusItemEntry.isEnabled = false
        menu.addItem(statusItemEntry)

        if !tapRunning {
            menu.addItem(withTitle: "Open Accessibility settings…",
                         action: #selector(openAccessibility), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Convert current word", action: #selector(noopHotkeyHint), keyEquivalent: "")
            .toolTip = "Hotkey: Control-Option-H"

        menu.addItem(.separator())
        addToggle(to: menu, title: "Auto-detect & convert", isOn: Settings.shared.autoConvert,
                  action: #selector(toggleAuto))
        addToggle(to: menu, title: "Fix typos (English)", isOn: Settings.shared.typoCorrectEN,
                  action: #selector(toggleTypoEN))
        addToggle(to: menu, title: "Fix typos (Hebrew)", isOn: Settings.shared.typoCorrectHE,
                  action: #selector(toggleTypoHE))
        addToggle(to: menu, title: "Pause", isOn: Settings.shared.paused,
                  action: #selector(togglePause))

        menu.addItem(.separator())
        let learned = NSMenuItem(title: "Learned words: \(engine.learnedCount)", action: nil, keyEquivalent: "")
        learned.isEnabled = false
        learned.toolTip = "Words you protected by undoing a conversion — never auto-changed."
        menu.addItem(learned)
        if engine.learnedCount > 0 {
            menu.addItem(withTitle: "Forget learned words", action: #selector(forgetLearned), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AutoLang", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
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

    @objc private func toggleAuto() { Settings.shared.autoConvert.toggle(); buildMenu() }
    @objc private func toggleTypoEN() { Settings.shared.typoCorrectEN.toggle(); buildMenu() }
    @objc private func toggleTypoHE() { Settings.shared.typoCorrectHE.toggle(); buildMenu() }
    @objc private func togglePause() { Settings.shared.paused.toggle(); buildMenu() }
}
