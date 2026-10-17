import Foundation

/// What happens when an emoji is picked.
enum PickAction: String, CaseIterable, Identifiable {
    case insert
    case copy
    case insertAndCopy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insert: "Insert"
        case .copy: "Copy"
        case .insertAndCopy: "Insert & Copy"
        }
    }
}

/// How an emoji is put into the host app.
enum InsertionMethod: String, CaseIterable, Identifiable {
    case type
    case paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: "Type"
        case .paste: "Paste"
        }
    }
}

/// Skin tone applied to the people and hand emoji that support one.
enum SkinTone: String, CaseIterable, Identifiable {
    case none
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    var id: String { rawValue }

    /// The Fitzpatrick modifier (U+1F3FB...U+1F3FF), nil for the default yellow.
    var modifier: Unicode.Scalar? {
        switch self {
        case .none: nil
        case .light: "\u{1F3FB}"
        case .mediumLight: "\u{1F3FC}"
        case .medium: "\u{1F3FD}"
        case .mediumDark: "\u{1F3FE}"
        case .dark: "\u{1F3FF}"
        }
    }

    var title: String {
        switch self {
        case .none: "Default"
        case .light: "Light"
        case .mediumLight: "Medium-Light"
        case .medium: "Medium"
        case .mediumDark: "Medium-Dark"
        case .dark: "Dark"
        }
    }
}

/// A key combination, stored as JSON under `AppSettings.Key.hotkey`.
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue` masked to command / option / control / shift.
    var modifiers: UInt
    var label: String

    /// cmd+; (keyCode 41 = kVK_ANSI_Semicolon, 1 << 20 = NSEvent.ModifierFlags.command).
    static let `default` = KeyShortcut(keyCode: 41, modifiers: 1 << 20, label: "⌘;")

    /// command | option | control | shift (`NSEvent.ModifierFlags` raw values).
    static let allowedModifiers: UInt = 1 << 20 | 1 << 19 | 1 << 18 | 1 << 17
    /// command | option | control: Shift alone would swallow plain typing.
    static let requiredModifiers: UInt = 1 << 20 | 1 << 19 | 1 << 18

    /// Only allowed modifiers, at least one of command / option / control.
    var isValid: Bool {
        modifiers & ~Self.allowedModifiers == 0 && modifiers & Self.requiredModifiers != 0
    }

    /// `shortcut` if valid, `.default` otherwise.
    static func validated(_ shortcut: KeyShortcut) -> KeyShortcut {
        shortcut.isValid ? shortcut : .default
    }
}

/// A user-defined `::alias:` that inserts `text`, stored as JSON under
/// `AppSettings.Key.customAliases`.
struct CustomAlias: Codable, Equatable, Identifiable {
    var alias: String
    var text: String

    var id: String { alias }
}

/// User settings in `UserDefaults.standard`. `Key` constants are shared with `@AppStorage`;
/// `registerDefaults()` makes both see the same defaults.
enum AppSettings {
    enum Key {
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkey = "hotkey"
        static let hotkeyAction = "hotkeyAction"
        static let menubarAction = "menubarAction"
        static let insertionMethod = "insertionMethod"
        static let inlineEnabled = "inlineEnabled"
        static let triggerSequence = "triggerSequence"
        static let triggerWindowMs = "triggerWindowMs"
        static let inlineAction = "inlineAction"
        static let menubarEnabled = "menubarEnabled"
        static let skinTone = "skinTone"
        static let ignoredApps = "ignoredApps"
        static let ignoredDomains = "ignoredDomains"
        static let customAliases = "customAliases"
        static let pausedUntil = "pausedUntil"
        static let emoticonsEnabled = "emoticonsEnabled"
        static let textArrowsEnabled = "textArrowsEnabled"
        static let welcomeShown = "welcomeShown"
    }

    static let defaultTriggerSequence = "::"
    static let triggerWindowRange = 100...1000
    static let maxCustomAliasTextLength = 200

    private static var store: UserDefaults { .standard }

    private static var defaultValues: [String: Any] {
        [
            Key.hotkeyEnabled: true,
            Key.hotkey: encode(KeyShortcut.default) ?? Data(),
            Key.hotkeyAction: PickAction.insert.rawValue,
            Key.menubarAction: PickAction.copy.rawValue,
            Key.insertionMethod: InsertionMethod.type.rawValue,
            Key.inlineEnabled: true,
            Key.triggerSequence: defaultTriggerSequence,
            Key.triggerWindowMs: 300,
            Key.inlineAction: PickAction.insert.rawValue,
            Key.menubarEnabled: true,
            Key.skinTone: SkinTone.none.rawValue,
            Key.ignoredApps: [String](),
            Key.ignoredDomains: [String](),
            Key.customAliases: encode([CustomAlias]()) ?? Data(),
            Key.pausedUntil: 0.0,
            Key.emoticonsEnabled: false,
            Key.textArrowsEnabled: false,
            Key.welcomeShown: false,
        ]
    }

    /// Call once at launch, before any setting is read.
    static func registerDefaults() {
        store.register(defaults: defaultValues)
    }

    static var hotkeyEnabled: Bool {
        get { store.bool(forKey: Key.hotkeyEnabled) }
        set { store.set(newValue, forKey: Key.hotkeyEnabled) }
    }

    static var hotkey: KeyShortcut {
        get {
            guard let data = store.data(forKey: Key.hotkey),
                  let shortcut = try? JSONDecoder().decode(KeyShortcut.self, from: data)
            else { return .default }
            return KeyShortcut.validated(shortcut)
        }
        set {
            // An invalid shortcut would swallow plain keystrokes system-wide.
            guard newValue.isValid else { return }
            store.set(encode(newValue), forKey: Key.hotkey)
        }
    }

    static var hotkeyAction: PickAction {
        get { rawEnum(Key.hotkeyAction, default: .insert) }
        set { store.set(newValue.rawValue, forKey: Key.hotkeyAction) }
    }

    static var menubarAction: PickAction {
        get { rawEnum(Key.menubarAction, default: .copy) }
        set { store.set(newValue.rawValue, forKey: Key.menubarAction) }
    }

    static var insertionMethod: InsertionMethod {
        get { rawEnum(Key.insertionMethod, default: .type) }
        set { store.set(newValue.rawValue, forKey: Key.insertionMethod) }
    }

    static var inlineEnabled: Bool {
        get { store.bool(forKey: Key.inlineEnabled) }
        set { store.set(newValue, forKey: Key.inlineEnabled) }
    }

    /// Falls back to `defaultTriggerSequence` when the stored value is invalid.
    static var triggerSequence: String {
        get {
            let stored = store.string(forKey: Key.triggerSequence) ?? ""
            return isValidTriggerSequence(stored) ? stored : defaultTriggerSequence
        }
        set {
            guard isValidTriggerSequence(newValue) else { return }
            store.set(newValue, forKey: Key.triggerSequence)
        }
    }

    /// Max delay between the trigger characters, clamped to `triggerWindowRange`.
    static var triggerWindowMs: Int {
        get { clampedTriggerWindow(store.integer(forKey: Key.triggerWindowMs)) }
        set { store.set(clampedTriggerWindow(newValue), forKey: Key.triggerWindowMs) }
    }

    static var inlineAction: PickAction {
        get { rawEnum(Key.inlineAction, default: .insert) }
        set { store.set(newValue.rawValue, forKey: Key.inlineAction) }
    }

    static var menubarEnabled: Bool {
        get { store.bool(forKey: Key.menubarEnabled) }
        set { store.set(newValue, forKey: Key.menubarEnabled) }
    }

    static var skinTone: SkinTone {
        get { rawEnum(Key.skinTone, default: .none) }
        set { store.set(newValue.rawValue, forKey: Key.skinTone) }
    }

    /// Bundle IDs of the apps where neither the inline trigger nor the hotkey fires.
    static var ignoredApps: [String] {
        get { store.stringArray(forKey: Key.ignoredApps) ?? [] }
        set { store.set(deduplicated(newValue), forKey: Key.ignoredApps) }
    }

    /// Domains (normalized) where the inline trigger is off; invalid entries are dropped.
    static var ignoredDomains: [String] {
        get { store.stringArray(forKey: Key.ignoredDomains) ?? [] }
        set {
            store.set(deduplicated(newValue.compactMap(normalizedDomain)), forKey: Key.ignoredDomains)
        }
    }

    /// Valid entries only, first one wins for a duplicated alias.
    static var customAliases: [CustomAlias] {
        get {
            guard let data = store.data(forKey: Key.customAliases),
                  let aliases = try? JSONDecoder().decode([CustomAlias].self, from: data)
            else { return [] }
            return validCustomAliases(aliases)
        }
        set { store.set(encode(validCustomAliases(newValue)), forKey: Key.customAliases) }
    }

    /// Converts emoticons typed as a word (`:)` → 🙂, see `EmoticonDetector`). Off by default.
    static var emoticonsEnabled: Bool {
        get { store.bool(forKey: Key.emoticonsEnabled) }
        set { store.set(newValue, forKey: Key.emoticonsEnabled) }
    }

    /// Converts text arrows typed as a word (`->` → →, see `EmoticonDetector.arrows`). Off by
    /// default: they also show up in code.
    static var textArrowsEnabled: Bool {
        get { store.bool(forKey: Key.textArrowsEnabled) }
        set { store.set(newValue, forKey: Key.textArrowsEnabled) }
    }

    /// The welcome window was shown once (new installs and 0.1.x upgraders alike start at false).
    static var welcomeShown: Bool {
        get { store.bool(forKey: Key.welcomeShown) }
        set { store.set(newValue, forKey: Key.welcomeShown) }
    }

    /// End of a pause (stored as seconds since 1970, 0 = not paused), nil when not paused.
    /// A date in the past is returned as is: the coordinator decides expiry.
    static var pausedUntil: Date? {
        get {
            let seconds = store.double(forKey: Key.pausedUntil)
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        set { store.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.pausedUntil) }
    }

    /// Alias: 1...`TriggerDetector.maxQueryLength` lowercase query characters, so that
    /// `::alias:` can be typed. Text: not blank, a single line without control characters,
    /// at most `maxCustomAliasTextLength` UTF-16 units.
    static func isValidCustomAlias(alias: String, text: String) -> Bool {
        let aliasValid = (1...TriggerDetector.maxQueryLength).contains(alias.count)
            && alias.allSatisfy(TriggerDetector.isQueryCharacter)
            && alias == alias.lowercased()
        // Only Cc counts as control: Cf holds the ZWJ and flag tag characters emoji need.
        let textValid = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.contains(where: \.isNewline)
            && !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
            && text.utf16.count <= maxCustomAliasTextLength
        return aliasValid && textValid
    }

    /// 1 to 3 printable characters: no whitespace, no control character, no query character
    /// (a letter, digit, `_`, `-` or `+` could never be told apart from the query).
    static func isValidTriggerSequence(_ sequence: String) -> Bool {
        let invalid = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        return !sequence.isEmpty && sequence.count <= 3
            && !sequence.unicodeScalars.contains(where: invalid.contains)
            && !sequence.contains(where: TriggerDetector.isQueryCharacter)
    }

    /// Bare lowercase host from what a user types or pastes (`https://www.GitHub.com/x` →
    /// `github.com`), nil if it is not a plausible domain.
    static func normalizedDomain(_ input: String) -> String? {
        var domain = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.contains("://") {
            domain = URL(string: domain)?.host ?? ""
        } else if let end = domain.firstIndex(where: { "/?#".contains($0) }) {
            domain = String(domain[..<end])
        }
        if let colon = domain.firstIndex(of: ":") {
            domain = String(domain[..<colon])
        }
        if let prefix = ["www.", "*."].first(where: domain.hasPrefix) {
            domain.removeFirst(prefix.count)
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !domain.isEmpty, domain.allSatisfy(allowed.contains),
              !domain.hasPrefix("."), !domain.hasSuffix("."),
              !domain.hasPrefix("-"), !domain.hasSuffix("-"),
              !domain.contains("..")
        else { return nil }
        return domain
    }

    /// A domain rule also covers its subdomains, but not look-alikes (`notgithub.com`).
    static func isIgnored(host: String, domains: [String]) -> Bool {
        let host = host.lowercased()
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func validCustomAliases(_ aliases: [CustomAlias]) -> [CustomAlias] {
        var seen = Set<String>()
        return aliases.filter {
            isValidCustomAlias(alias: $0.alias, text: $0.text) && seen.insert($0.alias).inserted
        }
    }

    private static func clampedTriggerWindow(_ ms: Int) -> Int {
        min(max(ms, triggerWindowRange.lowerBound), triggerWindowRange.upperBound)
    }

    /// Reads a String-backed enum the same way `@AppStorage` stores it.
    private static func rawEnum<T: RawRepresentable>(_ key: String, default fallback: T) -> T
    where T.RawValue == String {
        store.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}
