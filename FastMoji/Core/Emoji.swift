import Foundation

/// One entry of the bundled emoji data (`emoji.json`, generated from emojibase by
/// `scripts/regenerate-emoji-data.sh`).
struct Emoji: Codable, Hashable, Identifiable, Sendable {
    let emoji: String
    let description: String
    let category: String
    let aliases: [String]
    let tags: [String]
    /// vi / fr / es labels and tags (absent from older data).
    var keywords: [String]? = nil
    /// Emoji version the glyph first appeared in (absent from older data).
    var version: Double? = nil
    /// `skin_tones`: true when the emoji takes a skin tone (absent from the JSON otherwise).
    var skinTones: Bool? = nil
    /// `skin_tones_version`: Emoji version of the toned forms, only when newer than `version`.
    var skinTonesVersion: Double? = nil

    var id: String { emoji }

    enum CodingKeys: String, CodingKey {
        case emoji, description, category, aliases, tags, keywords, version
        case skinTones = "skin_tones"
        case skinTonesVersion = "skin_tones_version"
    }

    /// `emoji` with `tone` applied: the modifier goes after every modifier base and replaces the
    /// U+FE0F that follows it (✌️ → ✌🏽, 🕵️‍♂️ → 🕵🏽‍♂️, 🧑‍🤝‍🧑 → 🧑🏽‍🤝‍🧑🏽).
    func toned(_ tone: SkinTone) -> String {
        guard skinTones == true, let modifier = tone.modifier else { return emoji }
        var scalars = String.UnicodeScalarView()
        var afterBase = false
        for scalar in emoji.unicodeScalars {
            if afterBase, scalar == "\u{FE0F}" {
                afterBase = false
                continue
            }
            scalars.append(scalar)
            // 🤝 takes a tone on its own, never inside a sequence (🧑‍🤝‍🧑).
            afterBase = scalar.properties.isEmojiModifierBase
                && !(scalar == "\u{1F91D}" && emoji.unicodeScalars.count > 1)
            if afterBase { scalars.append(modifier) }
        }
        return String(scalars)
    }
}

enum EmojiCatalog {
    /// Loads `emoji.json` from the bundle, keeping file order (emojibase order is category order).
    /// Rows newer than `maxVersion` are dropped (the system font can't draw them); rows with no
    /// version are kept. Rows whose toned forms are newer than `maxVersion` lose `skinTones`.
    static func load(
        bundle: Bundle = .main,
        maxVersion: Double = maxEmojiVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
    ) -> [Emoji] {
        do {
            guard let url = bundle.url(forResource: "emoji", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try JSONDecoder().decode([Emoji].self, from: Data(contentsOf: url))
                .filter { ($0.version ?? 0) <= maxVersion }
                .map { emoji in
                    var emoji = emoji
                    if (emoji.skinTonesVersion ?? 0) > maxVersion { emoji.skinTones = nil }
                    return emoji
                }
        } catch {
            assertionFailure("Failed to load emoji.json: \(error)")
            return []
        }
    }

    /// Newest Emoji version the system font draws on `os`: each step is the macOS release that
    /// shipped it, and anything in between takes the lower step. Below macOS 14 isn't supported.
    static func maxEmojiVersion(for os: OperatingSystemVersion) -> Double {
        let steps: [(major: Int, minor: Int, version: Double)] = [
            (26, 4, 17.0),
            (15, 4, 16.0),
            (14, 4, 15.1),
        ]
        let current = (os.majorVersion, os.minorVersion)
        return steps.first { current >= ($0.major, $0.minor) }?.version ?? 15.0
    }
}
