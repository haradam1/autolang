import Foundation

/// Opt-in diagnostic log, privacy-minded: routine keystrokes are kept only in a
/// small in-memory ring buffer and never touch disk. Only "interesting" moments
/// — the `autolang` anchor, a language change, a conversion/undo, or a typo fix —
/// flush a window to disk: the recent context *before*, the event, and a short
/// tail *after*. So the file contains focused examples of behavior, not a full
/// transcript of everything you type.
///
/// Off by default; local only (~/Library/Logs/AutoLang/debug.log).
final class DebugLog {
    static let shared = DebugLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "com.autolang.debuglog")
    private var handle: FileHandle?

    // Windowing state (touched only on `queue`).
    private var ring: [String] = []          // recent routine lines, not yet written
    private var writeAfter = 0               // routine lines still to write post-event
    private let ringCap = 40                 // how much "before" context to keep
    private let afterCount = 15              // how much "after" context to write

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AutoLang", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("debug.log")
    }

    var enabled: Bool { Settings.shared.debugLogging }

    /// Routine event: kept in memory; written only if we're inside an open window.
    func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(Self.fmt.string(from: Date()))  \(message())\n"
        queue.async { self.record(line) }
    }

    /// Interesting event: flushes the preceding context and opens/extends a window.
    func event(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(Self.fmt.string(from: Date()))  \(message())\n"
        queue.async { self.mark(line) }
    }

    func begin(_ note: String) {
        guard enabled else { return }
        let line = "\n===== \(Self.fmt.string(from: Date()))  \(note) =====\n"
        queue.async { self.ring.removeAll(); self.writeAfter = 0; self.write(line) }
    }

    func clear() {
        queue.async {
            self.handle?.closeFile(); self.handle = nil
            self.ring.removeAll(); self.writeAfter = 0
            try? Data().write(to: self.fileURL)
        }
    }

    // MARK: - Windowing (on `queue`)

    private func record(_ line: String) {
        if writeAfter > 0 {
            write(line)
            writeAfter -= 1
            if writeAfter == 0 { write("---- (end) ----\n") }
        } else {
            ring.append(line)
            if ring.count > ringCap { ring.removeFirst(ring.count - ringCap) }
        }
    }

    private func mark(_ line: String) {
        if writeAfter == 0 {
            write("\n---- window ----\n")
            for l in ring { write(l) }   // the "before" context
            ring.removeAll()
        }
        write(line)                       // the event itself
        writeAfter = afterCount           // keep the next few routine lines ("after")
    }

    private func write(_ line: String) {
        // Recreate if the file was removed/rotated so we never silently stop.
        if handle != nil, !FileManager.default.fileExists(atPath: fileURL.path) {
            handle?.closeFile(); handle = nil
        }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: fileURL)
            handle?.seekToEndOfFile()
        }
        handle?.write(line.data(using: .utf8) ?? Data())
    }
}
