import Testing
@testable import FastMoji

struct AppSettingsTests {
    @Test("a stored shortcut without cmd/opt/ctrl falls back to the default")
    func shortcutWithoutCommandModifierFallsBack() {
        let plain = KeyShortcut(keyCode: 0, modifiers: 0, label: "")
        let shiftOnly = KeyShortcut(keyCode: 0, modifiers: 1 << 17, label: "⇧A")
        let optionShift = KeyShortcut(keyCode: 49, modifiers: 1 << 19 | 1 << 17, label: "⌥⇧Space")

        #expect(KeyShortcut.validated(plain) == .default)
        #expect(KeyShortcut.validated(shiftOnly) == .default)
        #expect(KeyShortcut.validated(optionShift) == optionShift)
    }
}
