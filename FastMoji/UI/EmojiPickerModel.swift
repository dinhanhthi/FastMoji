import Foundation
import Observation

struct PickerSection: Identifiable {
    let id: String
    let title: String
    let emojis: [Emoji]
}

struct PickerSelection: Equatable {
    var section: Int
    var index: Int
}

enum MoveDirection {
    case left, right, up, down
}

/// Read-only data shared by every picker, built once from `CatalogIndex.emojis` so sections,
/// lookups and search results hold the same `Emoji` values (`firstIndex(of:)` stays consistent).
final class PickerCatalog {
    let search: EmojiSearch
    /// Glyph → emoji, to turn the frecency history back into emojis.
    let byEmoji: [String: Emoji]
    let categorySections: [PickerSection]

    init(search: EmojiSearch) {
        let emojis = search.index.emojis
        self.search = search
        byEmoji = Dictionary(emojis.map { ($0.emoji, $0) }, uniquingKeysWith: { first, _ in first })
        categorySections = Self.groupByCategory(emojis)
    }

    /// One section per category, in catalog order.
    private static func groupByCategory(_ catalog: [Emoji]) -> [PickerSection] {
        var order: [String] = []
        var groups: [String: [Emoji]] = [:]
        for emoji in catalog {
            if groups[emoji.category] == nil { order.append(emoji.category) }
            groups[emoji.category, default: []].append(emoji)
        }
        return order.map { PickerSection(id: "category-\($0)", title: $0, emojis: groups[$0] ?? []) }
    }
}

/// Query, sections and keyboard selection shared by the menubar, hotkey and inline pickers.
/// Navigation is driven by method calls (key monitor or event tap), never by view focus.
@MainActor
@Observable
final class EmojiPickerModel {
    static let columns = 9
    static let frequentCount = 18

    var query = "" {
        didSet {
            // TextField bindings can write the same value back; keep the user's selection then.
            guard query != oldValue else { return }
            rebuild()
        }
    }

    /// Every section holds at least one emoji; empty when a search has no hits.
    private(set) var sections: [PickerSection] = []
    private(set) var selection: PickerSelection?
    /// True once the user moved the selection since the last query change / reset.
    private(set) var hasMoved = false
    /// Bumped by every `reset()` so views can react to a reopen even when nothing else changed.
    private(set) var resetCount = 0

    @ObservationIgnored var onConfirm: ((Emoji) -> Void)?

    @ObservationIgnored private let catalog: PickerCatalog
    @ObservationIgnored private let frecency: FrecencyStore

    init(catalog: PickerCatalog, frecency: FrecencyStore) {
        self.catalog = catalog
        self.frecency = frecency
        rebuild()
    }

    var selectedEmoji: Emoji? {
        guard let selection else { return nil }
        return sections[selection.section].emojis[selection.index]
    }

    func move(_ direction: MoveDirection) {
        hasMoved = true
        guard let current = selection else { return }
        let columns = Self.columns
        let count = sections[current.section].emojis.count
        let row = current.index / columns
        let col = current.index % columns
        let lastRow = (count - 1) / columns
        let hasNext = current.section + 1 < sections.count
        let hasPrevious = current.section > 0
        var next = current

        switch direction {
        case .right:
            if current.index + 1 < count {
                next.index += 1
            } else if hasNext {
                next = PickerSelection(section: current.section + 1, index: 0)
            }
        case .left:
            if current.index > 0 {
                next.index -= 1
            } else if hasPrevious {
                let previous = current.section - 1
                next = PickerSelection(section: previous, index: sections[previous].emojis.count - 1)
            }
        case .down:
            if row < lastRow {
                next.index = min(current.index + columns, count - 1)
            } else if hasNext {
                let following = current.section + 1
                next = PickerSelection(section: following, index: min(col, sections[following].emojis.count - 1))
            }
        case .up:
            if row > 0 {
                next.index -= columns
            } else if hasPrevious {
                let previous = current.section - 1
                let previousCount = sections[previous].emojis.count
                let previousLastRow = (previousCount - 1) / columns
                next = PickerSelection(
                    section: previous,
                    index: min(previousLastRow * columns + col, previousCount - 1)
                )
            }
        }
        selection = next
    }

    /// Selects `emoji` in section `section` (it may also appear in "Frequently Used").
    func select(_ emoji: Emoji, in section: Int) {
        guard sections.indices.contains(section),
              let index = sections[section].emojis.firstIndex(of: emoji) else { return }
        selection = PickerSelection(section: section, index: index)
    }

    /// Records the selected emoji in the history, then hands it to `onConfirm`.
    func confirm() {
        guard let emoji = selectedEmoji else { return }
        frecency.record(emoji.emoji)
        onConfirm?(emoji)
    }

    /// Clears the query and refreshes "Frequently Used" (call each time a picker opens).
    func reset() {
        if query.isEmpty {
            rebuild()
        } else {
            query = ""
        }
        resetCount += 1
    }

    private func rebuild() {
        if query.isEmpty {
            let frequent = frecency.top(Self.frequentCount).compactMap { catalog.byEmoji[$0] }
            sections = (frequent.isEmpty
                ? []
                : [PickerSection(id: "frequent", title: "Frequently Used", emojis: frequent)])
                + catalog.categorySections
        } else {
            let frecency = self.frecency
            let hits = catalog.search.search(query) { frecency.score($0) }
            sections = hits.isEmpty ? [] : [PickerSection(id: "results", title: "Results", emojis: hits)]
        }
        selection = sections.isEmpty ? nil : PickerSelection(section: 0, index: 0)
        hasMoved = false
    }
}
