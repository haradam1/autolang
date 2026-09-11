import Foundation
import CoreGraphics

/// Owns the CGEventTap: the global keyboard listener. It buffers the word in
/// progress and recognizes the manual-convert hotkey. Actual conversion is
/// delegated out (to `Engine`) so this file stays about the tap mechanics.
final class EventTapController {

    /// Manual-convert hotkey: Control+Option+H ("Hebrew/English"). Configurable later.
    private static let convertKeycode: Int64 = 0x04 // kVK_ANSI_H
    /// Clipboard-convert hotkey: Control+Option+V.
    private static let clipboardKeycode: Int64 = 0x09 // kVK_ANSI_V

    private let buffer = WordBuffer()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called when the user presses the manual-convert hotkey. Passes the
    /// keystrokes of the current word so the engine can re-render + switch.
    var onManualConvert: (([Keystroke]) -> Void)?

    /// Called on every committed word boundary: (word keystrokes, boundary keycode,
    /// editingExisting). `editingExisting` is true when the typing that produced
    /// this word began by editing into pre-existing text (backspaced past our
    /// buffer, or moved the caret) — so the word is a FRAGMENT, not a whole word,
    /// and must not be converted.
    var onWordBoundary: (([Keystroke], Int64, Bool) -> Void)?

    /// True while the current typing run is editing pre-existing on-screen text.
    private var editingExisting = false

    /// Called when the user presses backspace immediately after an auto-convert:
    /// the engine reverts it. Carries whatever the engine armed via `armUndo`.
    var onUndo: (() -> Void)?

    /// Called on a plain backspace (not an undo): the engine drops its
    /// retroactive lookback, since the on-screen text no longer matches.
    var onContextReset: (() -> Void)?

    /// Called on the clipboard-convert hotkey (Control+Option+V).
    var onClipboardConvert: (() -> Void)?

    /// Synchronous: called with the FIRST typed key after the caret moves. If it
    /// language-corrects the keystroke (switches layout + injects the char in the
    /// word's language), it returns true and we swallow the original key.
    var firstEditKeystroke: ((_ keycode: Int64, _ shifted: Bool) -> Bool)?

    /// Set when the caret moves (arrows/Home/End/PageUp-Down/click); the next
    /// typed key is the one we language-match.
    private var caretMoved = false

    /// Keys that move the caret without editing: arrows, Home, End, Page Up/Down.
    private static let navKeycodes: Set<Int64> = [0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79]

    /// Set by the engine right after an auto-conversion; the very next keystroke
    /// either triggers an undo (if it's backspace) or clears this.
    private var undoArmed = false

    // MARK: - Lifecycle

    /// Returns false if the tap couldn't be created (missing Accessibility perm).
    /// Idempotent: if a tap already exists, just reports success.
    func start() -> Bool {
        if tap != nil { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // .defaultTap => we can modify/swallow events
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// After a conversion, forget the current word (it's been re-rendered).
    func resetCurrentWord() { buffer.clear() }

    /// Engine calls this right after an auto-conversion so the next keystroke
    /// can offer a one-press undo.
    func armUndo() { undoArmed = true }

    // MARK: - Event handling (called from the C callback on the main run loop)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap on timeout / heavy load — re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Ignore events we posted ourselves (backspaces + injected text), or
        // they'd re-enter the buffer and masquerade as user backspaces.
        if event.getIntegerValueField(.eventSourceUserData) == AutoLangMagic {
            return Unmanaged.passUnretained(event)
        }

        // A mouse click repositions the caret. Mark it so the next typed key is
        // language-matched to the word clicked into, and drop the retro run.
        if type == .leftMouseDown {
            caretMoved = true
            editingExisting = true // clicked into text — subsequent typing edits it
            DebugLog.shared.log("CLICK (caret moved)")
            DispatchQueue.main.async { [weak self] in self?.onContextReset?() }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        DebugLog.shared.log("KEY \(Self.keyLabel(keycode))"
            + " shift=\(flags.contains(.maskShift) ? 1 : 0)"
            + " caps=\(flags.contains(.maskAlphaShift) ? 1 : 0)"
            + " cmd=\(flags.contains(.maskCommand) ? 1 : 0)"
            + " ctrl=\(flags.contains(.maskControl) ? 1 : 0)"
            + " opt=\(flags.contains(.maskAlternate) ? 1 : 0)")

        // Undo window: the first real keystroke after an auto-convert. If it's
        // backspace, revert instead of deleting; otherwise just disarm.
        if undoArmed {
            undoArmed = false
            if keycode == 0x33, !flags.contains(.maskCommand) {
                buffer.clear()
                DebugLog.shared.log("  → UNDO (backspace after auto-convert)")
                DispatchQueue.main.async { [weak self] in self?.onUndo?() }
                return nil // swallow the backspace; the engine restores the text
            }
            // fall through: this keystroke is handled normally below
        }

        // Manual-convert hotkey: Control+Option+H. Swallow it (return nil).
        if keycode == Self.convertKeycode,
           flags.contains(.maskControl), flags.contains(.maskAlternate),
           !flags.contains(.maskCommand) {
            let word = buffer.current
            DebugLog.shared.log("  → HOTKEY ⌃⌥H (manual convert)")
            DispatchQueue.main.async { [weak self] in self?.onManualConvert?(word) }
            return nil
        }

        // Clipboard-convert hotkey: Control+Option+V. Swallow it.
        if keycode == Self.clipboardKeycode,
           flags.contains(.maskControl), flags.contains(.maskAlternate),
           !flags.contains(.maskCommand) {
            DebugLog.shared.log("  → HOTKEY ⌃⌥V (clipboard convert)")
            DispatchQueue.main.async { [weak self] in self?.onClipboardConvert?() }
            return nil
        }

        // Caret-navigation keys: mark that the caret moved (the next typed key
        // gets language-matched). Fall through so the retro run resets & buffer flushes.
        if Self.navKeycodes.contains(keycode) {
            caretMoved = true
            editingExisting = true // moved the caret — subsequent typing edits text
            DebugLog.shared.log("  → NAV (caret moved)")
        } else if caretMoved {
            // First key after moving the caret: match the input language to the
            // word being edited, synchronously, before the character lands.
            caretMoved = false
            if KeyMap.isMappable(keycode), !flags.contains(.maskCommand),
               let handler = firstEditKeystroke {
                let shifted = flags.contains(.maskShift) != flags.contains(.maskAlphaShift)
                DebugLog.shared.log("  → FIRST-EDIT after caret move")
                if handler(keycode, shifted) {
                    buffer.clear()
                    buffer.append(Keystroke(code: keycode, shifted: shifted))
                    return nil // swallowed; the engine injected the corrected char
                }
            }
        }

        // Any command-key chord is a shortcut, not text — don't buffer it.
        if flags.contains(.maskCommand) {
            return Unmanaged.passUnretained(event)
        }

        // Backspace: mirror it in our buffer and invalidate any retro lookback.
        // Backspacing when our buffer is already empty means we're deleting into
        // pre-existing text — so what we type next edits an existing word.
        if keycode == 0x33 {
            if buffer.isEmpty { editingExisting = true }
            buffer.deleteLast()
            DispatchQueue.main.async { [weak self] in self?.onContextReset?() }
            return Unmanaged.passUnretained(event)
        }

        // Word boundary: flush and notify the auto-detector. An empty boundary
        // (double space, etc.) breaks contiguity, so reset the retro run.
        if KeyMap.wordBoundaryKeycodes.contains(keycode) {
            let finished = buffer.current
            let wasEditing = editingExisting
            buffer.flush()
            editingExisting = false // a boundary starts a fresh, clean word
            DispatchQueue.main.async { [weak self] in
                if finished.isEmpty { self?.onContextReset?() }
                else { self?.onWordBoundary?(finished, keycode, wasEditing) }
            }
            return Unmanaged.passUnretained(event)
        }

        // Ordinary key: accumulate. Effective uppercase = shift XOR caps-lock.
        // A non-mappable key (digit/symbol) breaks the run — reset the retro span.
        if !KeyMap.isMappable(keycode) {
            DispatchQueue.main.async { [weak self] in self?.onContextReset?() }
        }
        let shifted = flags.contains(.maskShift) != flags.contains(.maskAlphaShift)
        buffer.append(Keystroke(code: keycode, shifted: shifted))

        // Debug anchor: typing the physical keys for "autolang" drops a banner so
        // we can find the moment right before it (works in either layout, no space needed).
        if DebugLog.shared.enabled,
           KeyMap.render(buffer.current, as: .english).lowercased() == "autolang" {
            DebugLog.shared.log(">>>>>>>>>>>>>>> ANCHOR: 'autolang' — annoyance just above ^^^ <<<<<<<<<<<<<<<")
        }
        return Unmanaged.passUnretained(event)
    }
}

extension EventTapController {
    /// Human-readable label for a keycode, for the debug log.
    fileprivate static func keyLabel(_ code: Int64) -> String {
        if let e = KeyMap.entry(for: code) { return "'\(e.en)'" }
        switch code {
        case 0x31: return "SPACE"
        case 0x24: return "RETURN"
        case 0x30: return "TAB"
        case 0x33: return "BACKSPACE"
        case 0x7B: return "←"; case 0x7C: return "→"; case 0x7D: return "↓"; case 0x7E: return "↑"
        case 0x73: return "HOME"; case 0x77: return "END"
        default: return String(format: "key(0x%02X)", code)
        }
    }
}

// MARK: - C callback bridge

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
