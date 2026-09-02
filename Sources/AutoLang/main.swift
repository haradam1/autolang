import AppKit

// `--selftest` exercises the transliteration core without a GUI or permissions,
// so the mapping can be verified headlessly (in CI or over SSH).
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(SelfTest.failed ? 1 : 0)
}

// Normal launch: menu-bar app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
