import Foundation

/// Headless checks for the transliteration + detection core.
/// Run with `AutoLang --selftest`.
enum SelfTest {
    static var failed = false

    // Physical-key sequences (what the hardware sends, layout-independent).
    private static let shalomCodes: [Int64] = [0x00, 0x28, 0x20, 0x1F] // a,k,u,o
    private static let helloCodes: [Int64]  = [0x04, 0x0E, 0x25, 0x25, 0x1F] // h,e,l,l,o

    private static func ks(_ codes: [Int64], shiftFirst: Bool = false) -> [Keystroke] {
        codes.enumerated().map { Keystroke(code: $0.element, shifted: shiftFirst && $0.offset == 0) }
    }

    static func run() {
        // Transliteration both directions.
        check("shalom → Hebrew", KeyMap.render(ks(shalomCodes), as: .hebrew), "שלום")
        check("shalom → English", KeyMap.render(ks(shalomCodes), as: .english), "akuo")
        check("hello → English", KeyMap.render(ks(helloCodes), as: .english), "hello")
        check("hello → Hebrew", KeyMap.render(ks(helloCodes), as: .hebrew), "יקךךם")

        // Capitalization preserved via shift (issue 5).
        check("Hello (shift) → English capital", KeyMap.render(ks(helloCodes, shiftFirst: true), as: .english), "Hello")
        check("shift ignored for Hebrew", KeyMap.render(ks(shalomCodes, shiftFirst: true), as: .hebrew), "שלום")

        check("english→other is hebrew", Language.english.other == .hebrew ? "ok" : "no", "ok")

        // Detection oracle.
        let spell = SpellChecker()
        checkBool("spell: hello valid English", spell.isValid("hello", .english), true)
        checkBool("spell: akuo NOT valid English", spell.isValid("akuo", .english), false)
        checkBool("spell: שלום valid Hebrew", spell.isValid("שלום", .hebrew), true)
        checkBool("spell: יקךךם NOT valid Hebrew (orthography)", spell.isValid("יקךךם", .hebrew), false)
        checkBool("spell: Hebrew dictionary available", spell.hebrewAvailable, true)

        // Contractions recognized as valid English (not flipped to Hebrew).
        checkBool("spell: dont valid", spell.isValid("dont", .english), true)
        checkBool("spell: youre valid", spell.isValid("youre", .english), true)

        // Curated contraction correction — case preserved, ambiguous bare words left alone (issue 1).
        check("contraction: dont -> don't", spell.contractionCorrection("dont") ?? "nil", "don't")
        check("contraction: Dont -> Don't (case)", spell.contractionCorrection("Dont") ?? "nil", "Don't")
        check("contraction: were left alone (ambiguous bare)", spell.contractionCorrection("were") ?? "nil", "nil")
        check("contraction: its left alone (ambiguous bare)", spell.contractionCorrection("its") ?? "nil", "nil")
        check("contraction: hello has none", spell.contractionCorrection("hello") ?? "nil", "nil")

        // Safe-only typo correction: common typos fixed, names/substitutions left alone (issue 2).
        check("typo: helllo -> hello (repeat)", spell.topCorrection("helllo", .english) ?? "nil", "hello")
        check("typo: teh -> the (transpose)", spell.topCorrection("teh", .english) ?? "nil", "the")
        check("typo: Helllo -> Hello (case)", spell.topCorrection("Helllo", .english) ?? "nil", "Hello")
        check("typo: yaron NOT mangled to yarn", spell.topCorrection("yaron", .english) ?? "nil", "nil")
        check("typo: seperate left alone (substitution)", spell.topCorrection("seperate", .english) ?? "nil", "nil")

        // Multi-word span builder: covers every folded word, not just the last (issue 3).
        let solo = Engine.planConvert(asTyped: ["akuo"], corrected: ["שלום"])
        check("plan solo original", solo.original, "akuo ")
        check("plan solo corrected", solo.corrected, "שלום ")
        let run = Engine.planConvert(asTyped: ["vhs", "gk", "akuo"], corrected: ["הם", "על", "שלום"])
        check("plan run original covers all", run.original, "vhs gk akuo ")
        check("plan run corrected covers all", run.corrected, "הם על שלום ")

        // Caret language: language of the word under the cursor (issue: mixed words).
        func caretLang(_ t: String, _ c: Int) -> String {
            switch CaretLanguage.wordLanguage(in: t, caret: c) {
            case .some(.hebrew): return "he"; case .some(.english): return "en"; case .none: return "nil"
            }
        }
        check("caret inside Hebrew word", caretLang("שלום world", 2), "he")
        check("caret inside English word", caretLang("שלום world", 7), "en")
        check("caret at end of Hebrew word", caretLang("שלום world", 4), "he")
        check("caret at start of English word", caretLang("שלום world", 5), "en")

        print(failed ? "SELFTEST: FAIL" : "SELFTEST: PASS")
    }

    private static func check(_ name: String, _ got: String, _ want: String) {
        let ok = got == want
        if !ok { failed = true }
        print("[\(ok ? "PASS" : "FAIL")] \(name): got \"\(got)\" want \"\(want)\"")
    }

    private static func checkBool(_ name: String, _ got: Bool, _ want: Bool) {
        let ok = got == want
        if !ok { failed = true }
        print("[\(ok ? "PASS" : "FAIL")] \(name): got \(got) want \(want)")
    }
}
