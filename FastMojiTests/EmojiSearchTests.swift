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
        let ladyBeetle = emoji("🐞", "lady beetle", aliases: ["lady_beetle"], keywords: ["ladybird"])
        let search = EmojiSearch(catalog: [ladyBeetle])

        let results = search.search("yeet", frecency: { _ in 0 })

        #expect(results.isEmpty)
        // A contiguous in-word match still matches.
        #expect(search.search("eetle", frecency: { _ in 0 }).map(\.emoji) == ["🐞"])
        // A keyword needs a contiguous match even from a word start: `lbd` is scattered in
        // "ladybird" (and matches nothing else), while the prefix `ladybi` still matches; it only
        // exists in the keyword (no "i" in "lady beetle" / "lady_beetle").
        #expect(["lbd", "ladybi"].map { search.search($0, frecency: { _ in 0 }).count } == [0, 1])
    }

    @Test("a turned-off kind is hidden from search and exactMatch, but a custom alias still finds it")
    func turnedOffKindIsHiddenExceptCustomAlias() {
        let cat = emoji("🐱", "cat face", aliases: ["cat"])
        var command = emoji("⌘", "place of interest sign", aliases: ["cmd"])
        command.kind = .symbol
        let index = CatalogIndex(catalog: [cat, command])
        let plain = EmojiSearch(index: index)
        let custom = EmojiSearch(index: index, customAliases: [CustomAlias(alias: "cmd", text: "⌘")])

        #expect(plain.search("cmd", frecency: { _ in 0 }).map(\.emoji) == ["⌘"]) // found with every kind on
        #expect(plain.search("cmd", kinds: [.emoji], frecency: { _ in 0 }).isEmpty)
        #expect(plain.exactMatch("cmd", kinds: [.emoji]) == nil)
        #expect(custom.search("cmd", kinds: [.emoji], frecency: { _ in 0 }).map(\.emoji) == ["⌘"])
        #expect(custom.exactMatch("cmd", kinds: [.emoji])?.emoji == "⌘")
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
