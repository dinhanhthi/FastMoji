import Foundation

/// One entry of the bundled gemoji data (`emoji.json`).
struct Emoji: Codable, Hashable, Identifiable, Sendable {
    let emoji: String
    let description: String
    let category: String
    let aliases: [String]
    let tags: [String]
    /// gemoji's `skin_tones`: true when the emoji takes a skin tone (absent from the JSON otherwise).
    var skinTones: Bool? = nil

    var id: String { emoji }

    enum CodingKeys: String, CodingKey {
        case emoji, description, category, aliases, tags
        case skinTones = "skin_tones"
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
    /// Loads `emoji.json` from the bundle, keeping file order (gemoji order is category order).
    static func load(bundle: Bundle = .main) -> [Emoji] {
        do {
            guard let url = bundle.url(forResource: "emoji", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try JSONDecoder().decode([Emoji].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Failed to load emoji.json: \(error)")
            return []
        }
    }
}
