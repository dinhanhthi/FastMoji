import Foundation
import Observation

/// Usage history: count x exponential decay (half-life 7 days), persisted in UserDefaults.
@MainActor
@Observable
final class FrecencyStore {
    struct Entry: Codable {
        var count: Int
        var lastUsed: Date
    }

    private static let key = "frecency.v1"
    private static let halfLifeDays = 7.0

    private(set) var entries: [String: Entry]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func record(_ emoji: String, now: Date = .now) {
        var entry = entries[emoji] ?? Entry(count: 0, lastUsed: now)
        entry.count += 1
        entry.lastUsed = now
        entries[emoji] = entry
        save()
    }

    func score(_ emoji: String, now: Date = .now) -> Double {
        guard let entry = entries[emoji] else { return 0 }
        let ageDays = max(0, now.timeIntervalSince(entry.lastUsed)) / 86_400
        return Double(entry.count) * pow(0.5, ageDays / Self.halfLifeDays)
    }

    /// The `n` highest-scoring emoji; ties go to the most recently used.
    func top(_ n: Int, now: Date = .now) -> [String] {
        let ranked = entries
            .map { (emoji: $0.key, score: score($0.key, now: now), lastUsed: $0.value.lastUsed) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.lastUsed > $1.lastUsed }
        return ranked.prefix(max(0, n)).map(\.emoji)
    }

    func clear() {
        entries = [:]
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
