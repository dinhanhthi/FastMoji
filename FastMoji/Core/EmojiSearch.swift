import Foundation

private enum Score {
    static let base = 10.0
    static let exactAlias = 100.0
    static let prefix = 30.0
    static let wordBoundary = 15.0
    static let consecutive = 5.0
    static let gap = 1.0
    static let aliasWeight = 2.0
    static let descriptionWeight = 1.0
    static let tagWeight = 0.0
    /// Taken off symbol and kaomoji catalog scores, so emoji lead unless the match is much
    /// better; an exact alias (`cmd` → ⌘) still beats an emoji prefix match.
    static let nonEmojiPenalty = 25.0
    /// Max frecency bonus = 10 * 0.25 = 2.5, below one consecutive-char bonus.
    static let frecencyCap = 10.0
    static let frecencyFactor = 0.25
}

/// Read-only search data built once from the decoded rows and shared by every picker.
final class CatalogIndex: Sendable {
    fileprivate struct Field: Sendable {
        let scalars: [Unicode.Scalar]
        let isAlias: Bool
        /// Tags and keywords: matched contiguously only (see `score`).
        let isTag: Bool
        let weight: Double
    }

    /// The catalog with `keywords` dropped (they only live folded in `fields`, to save RAM).
    /// The single source of `Emoji` values, so results compare equal to everything built from it.
    let emojis: [Emoji]
    /// Folded, deduped searchable texts per emoji, same order as `emojis`.
    fileprivate let fields: [[Field]]
    /// Folded alias → index in `emojis`. Aliases are globally unique, so first in catalog order wins.
    fileprivate let exact: [String: Int]
    /// Glyph → index in `emojis`, so a custom alias whose text is a catalog glyph returns that entry.
    fileprivate let glyphs: [String: Int]

    init(catalog: [Emoji]) {
        var exact: [String: Int] = [:]
        glyphs = Dictionary(catalog.enumerated().map { ($1.emoji, $0) }, uniquingKeysWith: { first, _ in first })
        fields = catalog.enumerated().map { index, emoji in
            for alias in emoji.aliases {
                let key = Self.fold(alias)
                if exact[key] == nil { exact[key] = index }
            }
            // Highest weight first, so dedup keeps the best weight and its flags.
            let texts = emoji.aliases.map { ($0, true, false, Score.aliasWeight) }
                + [(emoji.description, false, false, Score.descriptionWeight)]
                + (emoji.tags + (emoji.keywords ?? [])).map { ($0, false, true, Score.tagWeight) }
            var seen: Set<String> = []
            return texts.compactMap { text, isAlias, isTag, weight in
                let folded = Self.fold(text)
                guard seen.insert(folded).inserted else { return nil }
                return Field(scalars: Array(folded.unicodeScalars), isAlias: isAlias, isTag: isTag, weight: weight)
            }
        }
        self.exact = exact
        emojis = catalog.map { emoji in
            var stripped = emoji
            stripped.keywords = nil
            return stripped
        }
    }

    /// Case- and accent-insensitive form used for both fields and queries ("Cười" → "cuoi").
    /// Folding keeps the Vietnamese "đ" (a letter, not d + accent) and the French "œ" (a ligature),
    /// so they are mapped by hand: "cœur" is found by typing `coeur`. Case folding already turns
    /// "Œ" into "œ".
    static func fold(_ text: String) -> String {
        // Most texts are plain ASCII, where folding is just lowercasing (and much faster).
        if text.utf8.allSatisfy({ $0 < 0x80 }) { return text.lowercased() }
        return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .replacingOccurrences(of: "œ", with: "oe")
    }
}

/// Fuzzy subsequence search over the emoji catalog and the user's custom aliases, ranked by text
/// score then frecency. Immutable: a change of custom aliases builds a new one over the same index.
struct EmojiSearch: Sendable {
    let index: CatalogIndex

    /// A result is a slot: an index in `index.emojis`, or `index.emojis.count` + an index in
    /// `synthesized` for a custom text that is not a catalog glyph.
    private struct CustomField: Sendable {
        let field: CatalogIndex.Field
        let slot: Int
    }

    /// One folded alias field per custom alias, scored like a catalog alias.
    private let customFields: [CustomField]
    /// Results built for custom texts that are not catalog glyphs, one per distinct text.
    private let synthesized: [Emoji]
    /// Folded custom alias → slot; checked before the catalog's exact map.
    private let customExact: [String: Int]

    init(index: CatalogIndex) {
        self.init(index: index, customAliases: [])
    }

    /// Builds only the custom layer (microseconds); `index` is shared, never rebuilt.
    init(index: CatalogIndex, customAliases: [CustomAlias]) {
        self.index = index
        var slots: [String: Int] = [:]
        var synthesized: [Emoji] = []
        var fields: [CustomField] = []
        var exact: [String: Int] = [:]
        for custom in customAliases {
            let key = CatalogIndex.fold(custom.alias)
            guard exact[key] == nil else { continue }
            // Aliases sharing a text share its slot, so the text is listed once (best score).
            let slot: Int
            if let known = slots[custom.text] ?? index.glyphs[custom.text] {
                slot = known
            } else {
                slot = index.emojis.count + synthesized.count
                synthesized.append(Emoji(
                    emoji: custom.text, description: custom.alias, category: "Custom",
                    aliases: [custom.alias], tags: []
                ))
            }
            slots[custom.text] = slot
            exact[key] = slot
            let field = CatalogIndex.Field(scalars: Array(key.unicodeScalars), isAlias: true, isTag: false, weight: Score.aliasWeight)
            fields.append(CustomField(field: field, slot: slot))
        }
        customFields = fields
        self.synthesized = synthesized
        customExact = exact
    }

    init(catalog: [Emoji]) {
        self.init(index: CatalogIndex(catalog: catalog))
    }

    /// Matching emoji, symbols and kaomoji, best first. Empty query returns the catalog order.
    /// Catalog ties keep catalog order (emoji, symbols, kaomoji), so grouping the result by `kind`
    /// in order of first appearance gives sections ordered by best score, emoji first on ties.
    /// Catalog rows of a kind outside `kinds` are skipped, unless a custom alias points at them:
    /// custom aliases always match.
    func search(_ query: String, kinds: ContentKinds = .all, frecency: (String) -> Double) -> [Emoji] {
        let folded = CatalogIndex.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let q = Array(folded.unicodeScalars)
        guard !q.isEmpty else { return index.emojis }

        var customScores: [Int: Double] = [:]
        for custom in customFields {
            guard let s = Self.score(q, in: custom.field) else { continue }
            customScores[custom.slot] = max(customScores[custom.slot] ?? s, s)
        }

        // On equal text scores a custom match goes first, as in `exactMatch`.
        var hits: [(slot: Int, score: Double, isCustom: Bool)] = []
        func add(_ slot: Int, catalogScore: Double?) {
            let custom = customScores[slot]
            guard let best = custom.map({ max($0, catalogScore ?? $0) }) ?? catalogScore else { return }
            let bonus = min(frecency(emoji(at: slot).emoji), Score.frecencyCap) * Score.frecencyFactor
            hits.append((slot, best + max(0, bonus), custom == best))
        }
        for (i, emojiFields) in index.fields.enumerated() {
            guard kinds.contains(kind: index.emojis[i].kind) else {
                add(i, catalogScore: nil) // kept only through a custom alias
                continue
            }
            var best: Double?
            for field in emojiFields {
                guard let s = Self.score(q, in: field) else { continue }
                best = max(best ?? s, s)
            }
            if index.emojis[i].kind != nil { best = best.map { $0 - Score.nonEmojiPenalty } }
            add(i, catalogScore: best)
        }
        for slot in customScores.keys where slot >= index.emojis.count {
            add(slot, catalogScore: nil)
        }
        hits.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.isCustom != $1.isCustom { return $0.isCustom }
            return $0.slot < $1.slot
        }
        return hits.map { emoji(at: $0.slot) }
    }

    /// The emoji whose alias is exactly `query` (folded), if any. Custom aliases win over the catalog
    /// and always match; a catalog alias of a kind outside `kinds` does not.
    func exactMatch(_ query: String, kinds: ContentKinds = .all) -> Emoji? {
        let key = CatalogIndex.fold(query)
        if let slot = customExact[key] { return emoji(at: slot) }
        guard let i = index.exact[key], kinds.contains(kind: index.emojis[i].kind) else { return nil }
        return index.emojis[i]
    }

    private func emoji(at slot: Int) -> Emoji {
        slot < index.emojis.count ? index.emojis[slot] : synthesized[slot - index.emojis.count]
    }

    /// Best subsequence score of `q` in `field`, trying every start position; nil if no match.
    /// Minimum match rule: a start inside a word counts only when the whole query follows it
    /// contiguously, so scattered letters don't match (`yeet` must not find "lady_beetle").
    /// Tags and keywords (many per emoji, often long phrases) need that at every start, word
    /// starts included: a scattered match there only adds unrelated results to the tail.
    private static func score(_ q: [Unicode.Scalar], in field: CatalogIndex.Field) -> Double? {
        let f = field.scalars
        guard q.count <= f.count else { return nil }
        if field.isAlias && f == q { return Score.exactAlias + Score.base + field.weight }

        let isPrefix = f.starts(with: q)
        var best: Double?
        for start in f.indices where f[start] == q[0] {
            let atBoundary = start == 0 || isSeparator(f[start - 1])
            if !atBoundary || field.isTag {
                // A contiguous match also scores best among in-word starts, so skipping the rest
                // is the same as allowing any match once the query is a substring.
                guard start + q.count <= f.count, f[start..<start + q.count].elementsEqual(q) else { continue }
            }
            guard let s = matchScore(q, f, from: start) else { break } // later starts cannot match either
            best = max(best ?? s, s)
        }
        guard let best else { return nil }
        return best + (isPrefix ? Score.prefix : 0) + field.weight
    }

    /// Greedy forward match of `q` in `f` starting with `q[0]` at `start`.
    private static func matchScore(_ q: [Unicode.Scalar], _ f: [Unicode.Scalar], from start: Int) -> Double? {
        var score = Score.base
        if start == 0 || isSeparator(f[start - 1]) { score += Score.wordBoundary }
        var last = start
        var qi = 1
        var fi = start + 1
        while qi < q.count && fi < f.count {
            if f[fi] == q[qi] {
                score += fi == last + 1 ? Score.consecutive : -Score.gap * Double(fi - last - 1)
                last = fi
                qi += 1
            }
            fi += 1
        }
        return qi == q.count ? score : nil
    }

    private static func isSeparator(_ c: Unicode.Scalar) -> Bool {
        c == "_" || c == "-" || c == " "
    }
}
