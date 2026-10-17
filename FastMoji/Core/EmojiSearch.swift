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
    /// Max frecency bonus = 10 * 0.25 = 2.5, below one consecutive-char bonus.
    static let frecencyCap = 10.0
    static let frecencyFactor = 0.25
}

/// Read-only search data built once from the decoded rows and shared by every picker.
final class CatalogIndex: Sendable {
    fileprivate struct Field: Sendable {
        let scalars: [Unicode.Scalar]
        let isAlias: Bool
        let weight: Double
    }

    /// The catalog with `keywords` dropped (they only live folded in `fields`, to save RAM).
    /// The single source of `Emoji` values, so results compare equal to everything built from it.
    let emojis: [Emoji]
    /// Folded, deduped searchable texts per emoji, same order as `emojis`.
    fileprivate let fields: [[Field]]
    /// Folded alias → index in `emojis`. Aliases are globally unique, so first in catalog order wins.
    fileprivate let exact: [String: Int]

    init(catalog: [Emoji]) {
        var exact: [String: Int] = [:]
        fields = catalog.enumerated().map { index, emoji in
            for alias in emoji.aliases {
                let key = Self.fold(alias)
                if exact[key] == nil { exact[key] = index }
            }
            // Highest weight first, so dedup keeps the alias flag and the best weight.
            let texts = emoji.aliases.map { ($0, true, Score.aliasWeight) }
                + [(emoji.description, false, Score.descriptionWeight)]
                + (emoji.tags + (emoji.keywords ?? [])).map { ($0, false, Score.tagWeight) }
            var seen: Set<String> = []
            return texts.compactMap { text, isAlias, weight in
                let folded = Self.fold(text)
                guard seen.insert(folded).inserted else { return nil }
                return Field(scalars: Array(folded.unicodeScalars), isAlias: isAlias, weight: weight)
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

/// Fuzzy subsequence search over the emoji catalog, ranked by text score then frecency.
struct EmojiSearch: Sendable {
    let index: CatalogIndex

    init(index: CatalogIndex) {
        self.index = index
    }

    init(catalog: [Emoji]) {
        self.init(index: CatalogIndex(catalog: catalog))
    }

    /// Matching emoji, best first. Empty query returns the catalog order.
    func search(_ query: String, frecency: (String) -> Double) -> [Emoji] {
        let folded = CatalogIndex.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let q = Array(folded.unicodeScalars)
        guard !q.isEmpty else { return index.emojis }

        var hits: [(index: Int, score: Double)] = []
        for (i, emojiFields) in index.fields.enumerated() {
            var best: Double?
            for field in emojiFields {
                guard let s = Self.score(q, in: field) else { continue }
                best = max(best ?? s, s)
            }
            guard let best else { continue }
            let bonus = min(frecency(index.emojis[i].emoji), Score.frecencyCap) * Score.frecencyFactor
            hits.append((i, best + max(0, bonus)))
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return hits.map { index.emojis[$0.index] }
    }

    /// The emoji whose alias is exactly `query` (folded), if any.
    func exactMatch(_ query: String) -> Emoji? {
        index.exact[CatalogIndex.fold(query)].map { index.emojis[$0] }
    }

    /// Best subsequence score of `q` in `field`, trying every start position; nil if no match.
    /// Minimum match rule: a start inside a word counts only when the whole query follows it
    /// contiguously, so scattered letters don't match (`yeet` must not find "lady_beetle").
    private static func score(_ q: [Unicode.Scalar], in field: CatalogIndex.Field) -> Double? {
        let f = field.scalars
        guard q.count <= f.count else { return nil }
        if field.isAlias && f == q { return Score.exactAlias + Score.base + field.weight }

        let isPrefix = f.starts(with: q)
        var best: Double?
        for start in f.indices where f[start] == q[0] {
            let atBoundary = start == 0 || isSeparator(f[start - 1])
            if !atBoundary {
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
