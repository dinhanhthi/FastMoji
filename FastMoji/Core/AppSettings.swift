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

/// User settings in `UserDefaults.standard`. `Key` constants are shared with `@AppStorage`;
/// `registerDefaults()` makes both see the same defaults.
enum AppSettings {
    enum Key {
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkey = "hotkey"
        static let hotkeyAction = "hotkeyAction"
        static let menubarAction = "menubarAction"
        static let insertionMethod = "insertionMethod"
    }

    private static var store: UserDefaults { .standard }

    private static var defaultValues: [String: Any] {
        [
            Key.hotkeyEnabled: true,
            Key.hotkey: encode(KeyShortcut.default) ?? Data(),
            Key.hotkeyAction: PickAction.insert.rawValue,
            Key.menubarAction: PickAction.copy.rawValue,
            Key.insertionMethod: InsertionMethod.type.rawValue,
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

    /// Reads a String-backed enum the same way `@AppStorage` stores it.
    private static func rawEnum<T: RawRepresentable>(_ key: String, default fallback: T) -> T
    where T.RawValue == String {
        store.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    private static func encode(_ shortcut: KeyShortcut) -> Data? {
        try? JSONEncoder().encode(shortcut)
    }
}
