# AutoLang

A macOS menu-bar tool that fixes wrong-layout Hebrew/English typing — you type
`akuo` meaning `שלום`, and AutoLang re-renders it and flips the active language.
It's the "Punto Switcher" idea, done natively for Hebrew/English on the Mac.

**Layout-fixing, not translation.** It re-maps the *keys you pressed* into the
other layout; it does not translate meaning.

Status: **Phase 1 skeleton** — builds, runs in the menu bar, converts the
current word on a hotkey, and shows the live language. Auto-detection and typo
correction are scaffolded (toggles present) but not yet implemented.

---

## Build & run

```bash
bash scripts/setup-signing.sh  # ONCE: stable signing identity so grants survive rebuilds
bash scripts/build.sh          # produces AutoLang.app (compiles + bundles + signs)
open AutoLang.app              # first run: grant Accessibility, then relaunch
# or install into /Applications and launch from there:
bash scripts/install.sh
```

### Signing / the re-grant treadmill

Ad-hoc signing gives the app a new code identity every build, which invalidates
the macOS Accessibility grant each time. `scripts/setup-signing.sh` creates a
**stable self-signed identity** (in its own keychain, its own password — not your
login) so the app's designated requirement stays constant and the grant persists
across rebuilds. `build.sh` uses it automatically when present, else falls back to
ad-hoc. Undo it with `scripts/remove-signing.sh`.

First launch prompts for **Accessibility** (System Settings ▸ Privacy &
Security ▸ Accessibility). Grant it and relaunch — TCC permission changes don't
apply to an already-running process. A `⌘ EN` / `⌘ עב` badge appears in the
menu bar (a `•` after it means the tap isn't active yet — usually missing
permission).

Verify the core mapping without any GUI or permissions:

```bash
./AutoLang.app/Contents/MacOS/AutoLang --selftest
```

> Build note: we compile with `swiftc` directly because this machine's Command
> Line Tools ship a broken SwiftPM manifest library (`swift build` fails to link
> the manifest). `Package.swift` is kept for when full Xcode is available.

## Use (Phase 1)

- Type a word in the wrong layout, then **⌃⌥H** to convert the current word and
  switch the active input source.
- **⌃⌥V** transliterates the **clipboard** EN⇄HE (fixes text pasted in the wrong layout).
- Auto-detect (when on) converts as you type; a brief menu-bar **flash** confirms
  each conversion (toggle: "Flash on convert").

## How it works

| Piece | File | Role |
|---|---|---|
| Key ↔ letter table | `KeyMap.swift` | keycode → English/Hebrew char (standard layouts) |
| Global listener | `EventTapController.swift` | `CGEventTap`; buffers the word, catches the hotkey, self-heals on tap-disable |
| Word buffer | `WordBuffer.swift` | in-progress word (grows into the multi-word window in Phase 2) |
| Layout read/switch | `InputSourceManager.swift` | TIS: current language + switch |
| Text replacement | `TextInjector.swift` | backspaces + unicode injection (needs Accessibility); tags its own events |
| Word validity | `SpellChecker.swift` | `NSSpellChecker` EN/HE + Hebrew final-letter orthography guard |
| Skip zones | `AppGuard.swift` | secure fields + excluded apps (terminals, editors, password mgrs) |
| Personal dict | `UserDictionary.swift` | protected words (never touched); auto-learns from your undos |
| Orchestration | `Engine.swift` | manual + auto convert, momentum, multi-word run, typo fix, undo/revert |
| Menu bar / onboarding | `AppDelegate.swift` | status item, badge, toggles, permission flow |
| Toggles | `Settings.swift` | auto-convert / typo EN / typo HE / pause (persisted) |

## Roadmap

- **Phase 1:** hotkey convert, layout switch, menu-bar language badge, permission onboarding, never-buffer command chords. ✅
- **Phase 2 — auto-detect:** ✅ `NSSpellChecker`-backed validity (English + Hebrew, with a Hebrew final-letter orthography guard), precision-first conversion on space, **language momentum** (multi-word context), **undo-on-backspace**, synthetic-event tagging, and **never-touch zones** (secure fields + excluded apps in `AppGuard.swift`). Cold-load race warmed up at init.
- **Phase 2-tail — deferred/retroactive:** ✅ a truly ambiguous word (valid both ways, no run yet) is **held**; when the next word disambiguates the run, the held word is converted **retroactively** (one-word lookback = the "analyze 2 words" behavior). Backspace/Return/app-switch drop the lookback so we never rewrite the wrong span.
  - Deferred still: a real **bigram frequency** table. Momentum + retroactive lookback already deliver the practical multi-word context; a bigram table would only refine same-language edge cases and needs an offline dataset. Left as a future refinement.
- **Phase 2.5 — typo correction:** ✅ per-language toggles. English inserts elided apostrophes from a **curated contraction list** (`dont`→`don't`, ambiguous bares like `were`/`its` left alone) and applies **safe-only** spelling fixes — repeated-letter collapse (`helllo`→`hello`) and adjacent transposition (`teh`→`the`, `recieve`→`receive`) — so names like `yaron` are never mangled. Hebrew guarded by orthography, off by default. Case preserved, undoable.
- **Quality pass (v0.4.0):**
  - **Capitalization preserved** — the buffer tracks shift/caps per key, so `Shalom`→Hebrew and typo fixes keep your casing (`Helllo`→`Hello`).
  - **Multi-word run** — ambiguous leading words are held as a *run* (up to 8), and the whole phrase flips once a later word disambiguates; digits/punctuation/double-space/backspace reset the run so spans stay valid.
  - **Personal dictionary** (`UserDictionary.swift`) — undo a conversion and that word is protected forever (never auto-changed); managed from the menu.
- **Phase 3 — polish:** ✅ version in menu (`AppInfo.swift`), ✅ browsable **learned-words** submenu (per-word delete), ✅ **statistics** (inline menu + HTML **dashboard**, `StatsReport.swift`), ✅ **user-editable per-app rules** (`AppRules.swift` + last-active-app tracking), ✅ **clipboard convert** (`ClipboardConverter.swift`, EN⇄HE on pasted text), ✅ **start-on-boot** via `SMAppService` (`LaunchAtLogin.swift`), ✅ **menu-bar icon styles** — four A·א brand marks, live-switchable (`MenuBarIcon.swift`; preview in `design/icon-preview.html`).
- **Phase 4 — distribution:** Developer ID signing + notarization (not App Store eligible due to keystroke tap).

## Permissions & privacy

AutoLang needs **Accessibility** permission because it reads keystrokes globally
and posts corrected ones — that's the whole job. It is keylogger-shaped by
necessity and privacy-first by design:

- The keystroke buffer is **in-memory only**, cleared at every word boundary.
- **Nothing is written to disk** except your own settings, learned words, and
  usage counts (all in local `UserDefaults`).
- **No network code anywhere** — grep the source; there are no URLs, sockets, or
  analytics. Everything stays on your Mac.
- It **stays out of password/secure fields** and any apps you exclude.

Because it's open source, you can verify all of the above yourself before
granting Accessibility.

## License

Licensed under the Apache License 2.0 — see [LICENSE](LICENSE).

## `phase0/`

A throwaway Hammerspoon spike (`autolang.lua`) that validated the mapping + hotkey
feel before the Swift build. Requires Hammerspoon (not installed here).
