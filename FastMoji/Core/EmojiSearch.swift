import Foundation

/// Fuzzy subsequence search over the emoji catalog, ranked by text score then frecency.
struct EmojiSearch: Sendable {
    private struct Field: Sendable {
        let scalars: [Unicode.Scalar]
        let isAlias: Bool
        let weight: Double
    }

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

    private let catalog: [Emoji]
    private let fields: [[Field]]

    init(catalog: [Emoji]) {
        self.catalog = catalog
        fields = catalog.map { emoji in
            emoji.aliases.map { Self.field($0, isAlias: true, weight: Score.aliasWeight) }
                + [Self.field(emoji.description, isAlias: false, weight: Score.descriptionWeight)]
                + emoji.tags.map { Self.field($0, isAlias: false, weight: Score.tagWeight) }
        }
    }

    /// Matching emoji, best first. Empty query returns the catalog order.
    func search(_ query: String, frecency: (String) -> Double) -> [Emoji] {
        let q = Array(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars)
        guard !q.isEmpty else { return catalog }

        var hits: [(index: Int, score: Double)] = []
        for (index, emojiFields) in fields.enumerated() {
            var best: Double?
            for field in emojiFields {
                guard let s = Self.score(q, in: field) else { continue }
                best = max(best ?? s, s)
            }
            guard let best else { continue }
            let bonus = min(frecency(catalog[index].emoji), Score.frecencyCap) * Score.frecencyFactor
            hits.append((index, best + max(0, bonus)))
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return hits.map { catalog[$0.index] }
    }

    private static func field(_ text: String, isAlias: Bool, weight: Double) -> Field {
        Field(scalars: Array(text.lowercased().unicodeScalars), isAlias: isAlias, weight: weight)
    }

    /// Best subsequence score of `q` in `field`, trying every start position; nil if no match.
    private static func score(_ q: [Unicode.Scalar], in field: Field) -> Double? {
        let f = field.scalars
        guard q.count <= f.count else { return nil }
        if field.isAlias && f == q { return Score.exactAlias + Score.base + field.weight }

        let isPrefix = f.starts(with: q)
        var best: Double?
        for start in f.indices where f[start] == q[0] {
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
