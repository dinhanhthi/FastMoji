import Testing
@testable import FastMoji

struct EmojiSearchTests {
    private func emoji(_ char: String, _ description: String, aliases: [String]) -> Emoji {
        Emoji(emoji: char, description: description, category: "Test", aliases: aliases, tags: [])
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
}
