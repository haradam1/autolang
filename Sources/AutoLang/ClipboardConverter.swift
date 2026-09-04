import AppKit

/// Converts the layout of arbitrary text (not keystrokes) — used for the
/// "Convert clipboard" command, which fixes text you pasted from elsewhere.
enum ClipboardConverter {

    /// Convert the current clipboard string EN⇄HE in place. Returns true if it
    /// changed anything.
    @discardableResult
    static func convertPasteboard() -> Bool {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string), !s.isEmpty else { return false }
        let converted = convert(s)
        guard converted != s else { return false }
        pb.clearContents()
        pb.setString(converted, forType: .string)
        return true
    }

    /// Direction is inferred from the text: any Hebrew letter ⇒ HE→EN, else EN→HE.
    static func convert(_ s: String) -> String {
        let hasHebrew = s.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) }
        var out = ""
        for ch in s {
            if hasHebrew {
                out.append(KeyMap.heToEnChar[ch] ?? ch)
            } else if let he = KeyMap.enToHeChar[Character(ch.lowercased())] {
                out.append(he) // Hebrew has no case
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
