import Foundation
import CoreGraphics

/// Owns the CGEventTap: the global keyboard listener. It buffers the word in
/// progress and recognizes the manual-convert hotkey. Actual conversion is
/// delegated out (to `Engine`) so this file stays about the tap mechanics.
final class EventTapController {

    /// Manual-convert hotkey: Control+Option+H ("Hebrew/English"). Configurable later.
    private static let convertKeycode: Int64 = 0x04 // kVK_ANSI_H

    private let buffer = WordBuffer()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called when the user presses the manual-convert hotkey. Passes the
    /// keycodes of the current word so the engine can re-render + switch.
    var onManualConvert: (([Int64]) -> Void)?

    /// Called on every committed word boundary: (word keycodes, boundary keycode).
    /// The engine decides whether to auto-convert.
    var onWordBoundary: (([Int64], Int64) -> Void)?

    /// Called when the user presses backspace immediately after an auto-convert:
    /// the engine reverts it. Carries whatever the engine armed via `armUndo`.
    var onUndo: (() -> Void)?

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
            (1 << CGEventType.flagsChanged.rawValue)

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

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Undo window: the first real keystroke after an auto-convert. If it's
        // backspace, revert instead of deleting; otherwise just disarm.
        if undoArmed {
            undoArmed = false
            if keycode == 0x33, !flags.contains(.maskCommand) {
                buffer.clear()
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
            DispatchQueue.main.async { [weak self] in self?.onManualConvert?(word) }
            return nil
        }

        // Any command-key chord is a shortcut, not text — don't buffer it.
        if flags.contains(.maskCommand) {
            return Unmanaged.passUnretained(event)
        }

        // Backspace: mirror it in our buffer.
        if keycode == 0x33 {
            buffer.deleteLast()
            return Unmanaged.passUnretained(event)
        }

        // Word boundary: flush and notify the auto-detector.
        if KeyMap.wordBoundaryKeycodes.contains(keycode) {
            let finished = buffer.current
            buffer.flush()
            if !finished.isEmpty {
                DispatchQueue.main.async { [weak self] in self?.onWordBoundary?(finished, keycode) }
            }
            return Unmanaged.passUnretained(event)
        }

        // Ordinary key: accumulate.
        buffer.append(keycode: keycode)
        return Unmanaged.passUnretained(event)
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
