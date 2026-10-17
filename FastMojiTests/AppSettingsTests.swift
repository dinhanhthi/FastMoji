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

    @Test("a domain rule matches itself and its subdomains, not a look-alike")
    func domainRuleCoversSubdomains() {
        let domains = ["github.com"]

        #expect(AppSettings.isIgnored(host: "github.com", domains: domains))
        #expect(AppSettings.isIgnored(host: "gist.github.com", domains: domains))
        #expect(!AppSettings.isIgnored(host: "notgithub.com", domains: domains))
    }

    @Test("pasted URLs and www. normalize to the bare host, garbage gives nil")
    func domainInputNormalizes() {
        #expect(AppSettings.normalizedDomain("https://www.GitHub.com/foo?x=1") == "github.com")
        #expect(AppSettings.normalizedDomain("github.com:443/path") == "github.com")
        #expect(AppSettings.normalizedDomain("") == nil)
        #expect(AppSettings.normalizedDomain("a b") == nil)
        #expect(AppSettings.normalizedDomain("foo..com") == nil)
    }
}
