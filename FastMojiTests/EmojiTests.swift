import Testing
@testable import FastMoji

struct EmojiTests {
    /// Real catalog entries, so a regenerated `emoji.json` without `skin_tones` fails too.
    private static let catalog = Dictionary(
        EmojiCatalog.load().map { ($0.emoji, $0) },
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
}
