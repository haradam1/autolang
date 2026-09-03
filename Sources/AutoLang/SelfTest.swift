import Foundation

/// Headless checks for the transliteration core. Run with `AutoLang --selftest`.
/// Covers the mapping in both directions on real Hebrew/English words.
enum SelfTest {
    static var failed = false

    // Physical-key keycode sequences (what the hardware sends, layout-independent).
    // "shalom": physical keys a,k,u,o  -> Hebrew שלום / English "akuo"
    private static let shalom: [Int64] = [0x00, 0x28, 0x20, 0x1F]
    // "hello": physical keys h,e,l,l,o -> English "hello" / Hebrew יקךךם
    private static let hello: [Int64]  = [0x04, 0x0E, 0x25, 0x25, 0x1F]

    static func run() {
        check("shalom → Hebrew", KeyMap.render(shalom, as: .hebrew), "שלום")
        check("shalom → English", KeyMap.render(shalom, as: .english), "akuo")
        check("hello → English", KeyMap.render(hello, as: .english), "hello")
        check("hello → Hebrew", KeyMap.render(hello, as: .hebrew), "יקךךם")

        // Round-trip: rendering EN then reading those same keys as HE is stable.
        check("english→other is hebrew", Language.english.other == .hebrew ? "ok" : "no", "ok")

        // Detection oracle: the decisions auto-convert relies on.
        let spell = SpellChecker()
        checkBool("spell: hello is valid English", spell.isValid("hello", .english), true)
        checkBool("spell: akuo is NOT valid English", spell.isValid("akuo", .english), false)
        checkBool("spell: שלום is valid Hebrew", spell.isValid("שלום", .hebrew), true)
        checkBool("spell: יקךךם is NOT valid Hebrew (orthography)", spell.isValid("יקךךם", .hebrew), false)
        checkBool("spell: Hebrew dictionary available", spell.hebrewAvailable, true)

        // Elided-apostrophe contractions must count as valid English (so they
        // are NOT mistaken for gibberish and flipped to Hebrew).
        checkBool("spell: dont valid via contraction", spell.isValid("dont", .english), true)
        checkBool("spell: im valid via contraction", spell.isValid("im", .english), true)
        checkBool("spell: youre valid via contraction", spell.isValid("youre", .english), true)
        checkBool("spell: akuo still NOT valid (no contraction)", spell.isValid("akuo", .english), false)

        // Typo correction (Phase 2.5)
        check("typo: dont -> don't (contraction)", spell.contractionCorrection("dont") ?? "nil", "don't")
        check("typo: hello has no contraction", spell.contractionCorrection("hello") ?? "nil", "nil")
        check("typo: helllo -> hello (spelling)", spell.topCorrection("helllo", .english) ?? "nil", "hello")
        check("typo: hello needs no correction", spell.topCorrection("hello", .english) ?? "nil", "nil")

        // Retroactive fold: when the 2nd word disambiguates, BOTH words are in
        // the replacement span — not only the second.
        let solo = Engine.planConvert(currentAsTyped: "akuo", currentOther: "שלום",
                                      deferredAsTyped: nil, deferredOther: nil)
        check("plan solo: original is just word2", solo.original, "akuo ")
        check("plan solo: corrected is just word2", solo.corrected, "שלום ")

        let both = Engine.planConvert(currentAsTyped: "akuo", currentOther: "שלום",
                                      deferredAsTyped: "vhs", deferredOther: "דבה")
        check("plan retro: original covers BOTH words", both.original, "vhs akuo ")
        check("plan retro: corrected covers BOTH words", both.corrected, "דבה שלום ")

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
