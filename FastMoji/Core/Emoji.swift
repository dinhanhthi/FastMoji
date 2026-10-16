import Foundation

/// One entry of the bundled gemoji data (`emoji.json`).
struct Emoji: Codable, Hashable, Identifiable, Sendable {
    let emoji: String
    let description: String
    let category: String
    let aliases: [String]
    let tags: [String]

    var id: String { emoji }
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
