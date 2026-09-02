import Foundation
import Carbon

/// Reads and switches the active keyboard input source (layout) via the
/// Text Input Sources (TIS) API.
final class InputSourceManager {

    /// The language of the currently-active input source.
    func currentLanguage() -> Language {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .english
        }
        return language(of: source)
    }

    /// Switch the active input source to one that types `lang`.
    /// Returns true if a matching source was found and selected.
    @discardableResult
    func select(_ lang: Language) -> Bool {
        guard let source = firstSource(for: lang) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Internals

    private func language(of source: TISInputSource) -> Language {
        guard let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return .english
        }
        let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String] ?? []
        return langs.contains("he") ? .hebrew : .english
    }

    private func firstSource(for lang: Language) -> TISInputSource? {
        // Only keyboard layouts / input modes that can actually be selected.
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] else { return nil }

        for source in list where language(of: source) == lang {
            return source
        }
        return nil
    }
}
