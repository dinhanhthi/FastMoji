import Foundation
import Testing
@testable import FastMoji

@MainActor
struct EmojiPickerModelTests {
    /// Searches "foo" over `emojiCount` emoji then `kaomojiCount` kaomoji, all matching equally,
    /// so the results are one 9-column emoji section then one 3-column kaomoji section.
    /// `body` gets a model whose history lives in a throwaway UserDefaults suite.
    private func withSearchModel(
        emojiCount: Int,
        kaomojiCount: Int,
        _ body: (EmojiPickerModel) throws -> Void
    ) throws {
        let suite = "FastMojiTests.EmojiPickerModel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let emojis = (0..<emojiCount).map {
            Emoji(emoji: "e\($0)", description: "foo \($0)", category: "Test", aliases: ["foo_\($0)"], tags: [])
        }
        let kaomojis = (0..<kaomojiCount).map {
            Emoji(
                emoji: "k\($0)", description: "foo \($0)", category: "Test", aliases: ["foo_\($0)"], tags: [],
                kind: .kaomoji
            )
        }
        let index = CatalogIndex(catalog: emojis + kaomojis)
        let model = EmojiPickerModel(
            catalog: PickerCatalog(index: index),
            search: EmojiSearch(index: index),
            frecency: FrecencyStore(defaults: defaults)
        )
        model.query = "foo"
        try #require(model.sections.map(\.columns) == [9, 3])
        try #require(model.sections.map(\.emojis.count) == [emojiCount, kaomojiCount])
        try body(model)
    }

    private func select(_ model: EmojiPickerModel, section: Int, index: Int) {
        model.select(model.sections[section].emojis[index], in: section)
    }

    @Test("down from the last emoji row clamps the column to 2, up from kaomoji keeps the column")
    func moveBetweenNineAndThreeColumns() throws {
        // 22 emoji: the last row holds indices 18...21 (columns 0...3).
        try withSearchModel(emojiCount: 22, kaomojiCount: 4) { model in
            select(model, section: 0, index: 21)
            model.move(.down)
            #expect(model.selection == PickerSelection(section: 1, index: 2))

            select(model, section: 1, index: 1)
            model.move(.up)
            #expect(model.selection == PickerSelection(section: 0, index: 19))
        }
    }

    @Test("a column past the target row's last item lands on that item")
    func moveClampsToLastItem() throws {
        // 20 emoji: the last row holds indices 18 and 19 only.
        try withSearchModel(emojiCount: 20, kaomojiCount: 4) { model in
            select(model, section: 1, index: 2)
            model.move(.up)
            #expect(model.selection == PickerSelection(section: 0, index: 19))
        }
    }
}
