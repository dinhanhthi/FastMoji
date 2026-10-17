import Testing
@testable import FastMoji

struct EmojiSearchTests {
    private func emoji(_ char: String, _ description: String, aliases: [String], keywords: [String]? = nil) -> Emoji {
        Emoji(emoji: char, description: description, category: "Test", aliases: aliases, tags: [], keywords: keywords)
    }

    @Test("prefix match outranks subsequence-only match")
    func prefixOutranksSubsequence() {
        // The expected loser comes first in the catalog, so a scoring tie would fail the test.
        let scattered = emoji("😭", "loudly crying face", aliases: ["sob_and_mild"])
        let smile = emoji("😄", "grinning face", aliases: ["smile"])
        let search = EmojiSearch(catalog: [scattered, smile])

        let results = search.search("smi", frecency: { _ in 0 })

        #expect(results.map(\.emoji) == ["😄", "😭"])
    }

    @Test("frecency breaks ties between equal text scores")
    func frecencyBreaksTies() {
        let red = emoji("❤️", "red heart", aliases: ["red_heart"])
        let blue = emoji("💙", "blue heart", aliases: ["blue_heart"])
        let search = EmojiSearch(catalog: [red, blue])
        let usage = ["💙": 3.0]

        let results = search.search("heart", frecency: { usage[$0] ?? 0 })

        #expect(results.map(\.emoji) == ["💙", "❤️"])
    }

    @Test("accents are ignored: cuoi finds the vi keyword cười")
    func accentsAreFolded() {
        let laughing = emoji("😆", "grinning squinting face", aliases: ["laughing"], keywords: ["cười"])
        let crying = emoji("😢", "crying face", aliases: ["cry"], keywords: ["khóc"])
        let search = EmojiSearch(catalog: [crying, laughing])

        let results = search.search("cuoi", frecency: { _ in 0 })

        #expect(results.map(\.emoji) == ["😆"])
    }

    @Test("đ is searched as d: dong ho finds đồng hồ")
    func dStrokeFoldsToD() {
        let clock = emoji("🕰️", "mantelpiece clock", aliases: ["mantelpiece_clock"], keywords: ["đồng hồ"])
        let search = EmojiSearch(catalog: [clock])

        let results = search.search("dong ho", frecency: { _ in 0 })

        #expect(results.map(\.emoji) == ["🕰️"])
    }

    @Test("scattered letters inside a word don't match: yeet does not find lady_beetle")
    func scatteredLettersDoNotMatch() {
        let ladyBeetle = emoji("🐞", "lady beetle", aliases: ["lady_beetle"])
        let search = EmojiSearch(catalog: [ladyBeetle])

        let results = search.search("yeet", frecency: { _ in 0 })

        #expect(results.isEmpty)
        // A contiguous in-word match still matches.
        #expect(search.search("eetle", frecency: { _ in 0 }).map(\.emoji) == ["🐞"])
    }

    @Test("a custom alias wins over the catalog alias, and a non-catalog text is synthesized")
    func customAliasOutranksCatalog() {
        let cat = emoji("🐱", "cat face", aliases: ["cat"])
        let customs = [
            CustomAlias(alias: "cat", text: "🐈"),
            CustomAlias(alias: "shrug", text: #"¯\_(ツ)_/¯"#),
        ]
        let search = EmojiSearch(index: CatalogIndex(catalog: [cat]), customAliases: customs)

        #expect(search.exactMatch("cat")?.emoji == "🐈")
        #expect(search.exactMatch("shrug")?.emoji == #"¯\_(ツ)_/¯"#)
    }
}
