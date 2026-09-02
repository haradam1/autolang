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

- Type a word in the wrong layout.
- Press **Control-Option-H** to convert the current word and switch the active
  input source. (Press it before the space — committed-word conversion is Phase 2.)

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
| Orchestration | `Engine.swift` | manual + auto convert, momentum, undo/revert |
| Menu bar / onboarding | `AppDelegate.swift` | status item, badge, toggles, permission flow |
| Toggles | `Settings.swift` | auto-convert / typo EN / typo HE / pause (persisted) |

## Roadmap

- **Phase 1:** hotkey convert, layout switch, menu-bar language badge, permission onboarding, never-buffer command chords. ✅
- **Phase 2 — auto-detect:** ✅ done — `NSSpellChecker`-backed validity (English + Hebrew, with a Hebrew final-letter orthography guard), precision-first conversion on space, **language momentum** (multi-word context), **undo-on-backspace**, synthetic-event tagging, and **never-touch zones** (secure fields + excluded apps in `AppGuard.swift`). Cold-load race warmed up at init.
  - Still open: **deferred/retroactive** conversion (hold an ambiguous word 1 turn, convert the run once the next word disambiguates) and a real **bigram** table (momentum is the lighter stand-in).
- **Phase 2.5 — typo correction:** English (SymSpell/Hunspell), then conservative Hebrew (Hspell). Independent toggles already in the menu.
- **Phase 3 — polish:** user-editable per-app rules, learning dictionary, clipboard convert, pause/feedback, start-on-boot via `SMAppService`.
- **Phase 4 — distribution:** Developer ID signing + notarization (not App Store eligible due to keystroke tap).

## Privacy

Keylogger-shaped by necessity, privacy-first by design: the keystroke buffer is
in-memory only, cleared at every word boundary, never written to disk, and there
is no network code anywhere in the app.

## `phase0/`

A throwaway Hammerspoon spike (`autolang.lua`) that validated the mapping + hotkey
feel before the Swift build. Requires Hammerspoon (not installed here).
