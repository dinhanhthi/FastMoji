import Foundation
import Testing
@testable import FastMoji

struct EmojiTests {
    /// Real catalog entries, so a regenerated `emoji.json` without `skin_tones` fails too.
    /// A fixed `maxVersion` keeps the tests independent of the macOS they run on.
    private static let catalog = Dictionary(
        EmojiCatalog.load(maxVersion: 17.0).map { ($0.emoji, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    @Test("the modifier replaces the U+FE0F after the base")
    func modifierReplacesVariationSelector() throws {
        let victory = try #require(Self.catalog["✌️"])

        #expect(victory.toned(.medium) == "✌🏽")
    }

    @Test("both people take the tone, the handshake between them does not")
    func everyPersonTakesTheTone() throws {
        let holdingHands = try #require(Self.catalog["🧑‍🤝‍🧑"])

        #expect(holdingHands.toned(.medium) == "🧑🏽‍🤝‍🧑🏽")
    }

    @Test("no tone, or an emoji without skin tones, keeps the base")
    func untonedKeepsTheBase() throws {
        let wave = try #require(Self.catalog["👋"])
        let grinning = try #require(Self.catalog["😀"])

        #expect(wave.toned(.none) == "👋")
        #expect(grinning.toned(.dark) == "😀")
    }

    @Test("the macOS version picks the newest drawable Emoji version, and newer rows are dropped")
    func osVersionFiltersNewerEmoji() {
        func os(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
            OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        }
        #expect(EmojiCatalog.maxEmojiVersion(for: os(14, 0)) == 15.0)
        #expect(EmojiCatalog.maxEmojiVersion(for: os(15, 4)) == 16.0)
        #expect(EmojiCatalog.maxEmojiVersion(for: os(26, 4)) == 17.0)

        let all = EmojiCatalog.load(maxVersion: 17.0)
        let filtered = EmojiCatalog.load(maxVersion: 15.0)

        #expect(all.contains { ($0.version ?? 0) > 15.0 })
        #expect(filtered.allSatisfy { ($0.version ?? 0) <= 15.0 })
        #expect(filtered.count == all.filter { ($0.version ?? 0) <= 15.0 }.count)
        // 👯 is Emoji 0.6, but its toned forms (skin_tones_version 17) are not drawable on 15.0.
        #expect(filtered.contains { $0.emoji == "👯" && $0.skinTonesVersion == 17 && $0.skinTones == nil })
    }

    @Test("ids are unique across emoji, symbols and kaomoji in the bundled files")
    func idsAreUniqueAcrossKinds() {
        // Loaded fresh: `catalog` above dedupes by glyph, which would hide a collision.
        let all = EmojiCatalog.load(maxVersion: 17.0)
        let duplicates = Dictionary(grouping: all, by: \.id).filter { $1.count > 1 }.keys

        // Both extra files must load, or the check would pass on emoji alone.
        #expect(all.contains { $0.kind == .symbol })
        #expect(all.contains { $0.kind == .kaomoji })
        #expect(duplicates.isEmpty, "duplicate ids: \(duplicates.sorted())")
    }

    @Test("typed text is cut into key-event chunks of at most 20 UTF-16 units, between Characters")
    func typedTextChunksKeepCharacters() {
        let text = "( ͡° ͜ʖ ͡°)ヽ(°〇°)ﾉ¯\\_(ツ)_/¯👨‍👩‍👧‍👦🇻🇳🏴󠁧󠁢󠁳󠁣󠁴󠁿"
        let chunks = EmojiInserter.chunks(of: text)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf16.count <= EmojiInserter.maxChunkLength })
        // A split grapheme would add Characters.
        #expect(chunks.reduce(0) { $0 + $1.count } == text.count)
    }
}
