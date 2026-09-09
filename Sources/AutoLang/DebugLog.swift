import Foundation

/// Opt-in diagnostic log for tuning behavior. When enabled it records every
/// keystroke, deletion, word decision, and language change (ours and the
/// system's) to a local file so we can analyze what actually happened.
///
/// PRIVACY: this deliberately records the text you type. It's off by default,
/// writes only to a local file (~/Library/Logs/AutoLang/debug.log), and never
/// leaves your Mac. Turn it off and clear the log when you're done debugging.
final class DebugLog {
    static let shared = DebugLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "com.autolang.debuglog")
    private var handle: FileHandle?

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AutoLang", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("debug.log")
    }

    var enabled: Bool { Settings.shared.debugLogging }

    /// Append a line (message built lazily, so logging is free when disabled).
    func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(Self.fmt.string(from: Date()))  \(message())\n"
        queue.async { self.append(line) }
    }

    /// Marker written when logging is turned on, so sessions are separable.
    func begin(_ note: String) {
        guard enabled else { return }
        let line = "\n===== \(Self.fmt.string(from: Date()))  \(note) =====\n"
        queue.async { self.append(line) }
    }

    func clear() {
        queue.async {
            self.handle?.closeFile()
            self.handle = nil
            try? Data().write(to: self.fileURL)
        }
    }

    private func append(_ line: String) {
        // If the file was removed/rotated out from under us, drop the stale
        // handle so we recreate it — otherwise a days-long session could stop
        // writing silently.
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
