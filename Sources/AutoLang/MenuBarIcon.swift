import AppKit

/// Brand icon styles for the menu bar. Each is a template image (monochrome,
/// auto-tinted for light/dark) that combines a unique mark with the *current*
/// language. The brand idea: A (Latin) + א (Hebrew aleph) — the first letters
/// of both alphabets. Live-switchable from the menu.
enum IconStyle: String, CaseIterable {
    case duo      // A · א monogram, active side emphasized
    case pill     // active letter inside a rounded badge
    case ring     // active letter inside a coin/ring
    case classic  // speech bubble + EN/עב text (original)

    var title: String {
        switch self {
        case .duo:     return "Duo monogram  (A·א)"
        case .pill:    return "Pill badge"
        case .ring:    return "Ring coin"
        case .classic: return "Classic bubble"
        }
    }
}

enum MenuBarIcon {
    static let height: CGFloat = 18

    static func image(language: Language, style: IconStyle) -> NSImage {
        switch style {
        case .duo:     return duo(language)
        case .pill:    return framed(language, circle: false)
        case .ring:    return framed(language, circle: true)
        case .classic: return classic(language)
        }
    }

    /// Shown when the tap isn't armed (needs Accessibility).
    static func warning() -> NSImage {
        let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                          accessibilityDescription: "AutoLang needs Accessibility permission")
        img?.isTemplate = true
        return img ?? NSImage()
    }

    // MARK: - Styles

    private static func duo(_ lang: Language) -> NSImage {
        make(width: 30) { r in
            let he = lang == .hebrew
            // Stable layout (A left, א right); the active script is bold + solid,
            // the other is small + faded — so the mark always shows both alphabets.
            text("A", at: NSPoint(x: 8, y: r.midY), size: he ? 9 : 13,
                 weight: he ? .regular : .bold, alpha: he ? 0.3 : 1)
            text("·", at: NSPoint(x: 15, y: r.midY), size: 11, weight: .bold, alpha: 0.45)
            text("א", at: NSPoint(x: 22, y: r.midY), size: he ? 13 : 9,
                 weight: he ? .bold : .regular, alpha: he ? 1 : 0.3)
        }
    }

    private static func framed(_ lang: Language, circle: Bool) -> NSImage {
        make(width: circle ? 20 : 22) { r in
            let box = r.insetBy(dx: 1.6, dy: 1.6)
            let path = circle
                ? NSBezierPath(ovalIn: box)
                : NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            text(lang == .hebrew ? "א" : "A", at: NSPoint(x: r.midX, y: r.midY - 0.5),
                 size: 11, weight: .semibold, alpha: 1)
        }
    }

    private static func classic(_ lang: Language) -> NSImage {
        make(width: 34) { r in
            if let sym = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: nil) {
                sym.isTemplate = true
                let s: CGFloat = 14
                sym.draw(in: NSRect(x: 0, y: (r.height - s) / 2, width: s, height: s))
            }
            text(lang.badge, at: NSPoint(x: 25, y: r.midY), size: 10, weight: .semibold, alpha: 1)
        }
    }

    // MARK: - Drawing helpers

    private static func make(width: CGFloat, _ draw: (NSRect) -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        NSColor.black.set()
        draw(NSRect(x: 0, y: 0, width: width, height: height))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private static func text(_ s: String, at center: NSPoint, size: CGFloat,
                             weight: NSFont.Weight, alpha: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.black.withAlphaComponent(alpha)
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
    }
}
