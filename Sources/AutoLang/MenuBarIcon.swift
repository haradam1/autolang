import AppKit

/// Brand icon styles for the menu bar. Each is a template image (monochrome,
/// auto-tinted for light/dark) that combines a unique mark with the *current*
/// language. The brand idea: A (Latin) + א (Hebrew aleph) — the first letters
/// of both alphabets. Live-switchable from the menu.
enum IconStyle: String, CaseIterable {
    case duo      // A · א monogram, active side emphasized
    case pill     // active letter inside a rounded badge
    case swap     // active letter wrapped by a circular (convert) arrow
    case classic  // speech bubble + EN/עב text (original)

    var title: String {
        switch self {
        case .duo:     return "Duo monogram  (A·א)"
        case .pill:    return "Pill badge"
        case .swap:    return "Swap arrow  (⟳)"
        case .classic: return "Classic bubble"
        }
    }
}

enum MenuBarIcon {
    static let height: CGFloat = 18

    static func image(language: Language, style: IconStyle) -> NSImage {
        switch style {
        case .duo:     return duo(language)
        case .pill:    return framed(language)
        case .swap:    return swapArrow(language)
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

    private static func framed(_ lang: Language) -> NSImage {
        make(width: 22) { r in
            let box = r.insetBy(dx: 1.6, dy: 1.6)
            let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            text(lang == .hebrew ? "א" : "A", at: NSPoint(x: r.midX, y: r.midY - 0.5),
                 size: 11, weight: .semibold, alpha: 1)
        }
    }

    /// The active letter wrapped by a circular arrow — the "convert" mark.
    private static func swapArrow(_ lang: Language) -> NSImage {
        make(width: 21) { r in
            let c = NSPoint(x: r.midX, y: r.midY - 0.5)
            let radius: CGFloat = 7.3
            // Sweep the long way (~310°) counter-clockwise, leaving a gap at the
            // top where the arrowhead sits.
            let startAngle: CGFloat = 120
            let endAngle: CGFloat = 70

            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            arc.lineWidth = 1.5
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            // Arrowhead at the arc's end, pointing along the CCW tangent.
            let a = Double(endAngle) * .pi / 180
            let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
            let tip = NSPoint(x: c.x + radius * ca, y: c.y + radius * sa)
            let tan = NSPoint(x: -sa, y: ca)   // counter-clockwise tangent
            let nrm = NSPoint(x: ca, y: sa)    // radial
            let head = NSBezierPath()
            head.move(to: NSPoint(x: tip.x + tan.x * 3.0, y: tip.y + tan.y * 3.0))
            head.line(to: NSPoint(x: tip.x - tan.x * 1.6 + nrm.x * 2.4, y: tip.y - tan.y * 1.6 + nrm.y * 2.4))
            head.line(to: NSPoint(x: tip.x - tan.x * 1.6 - nrm.x * 2.4, y: tip.y - tan.y * 1.6 - nrm.y * 2.4))
            head.close()
            NSColor.black.setFill()
            head.fill()

            text(lang == .hebrew ? "א" : "A", at: c, size: 9.5, weight: .bold, alpha: 1)
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
