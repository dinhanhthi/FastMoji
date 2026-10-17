import Foundation

/// Pure state machine that recognises a typed text conversion (an emoticon such as `:)`, `<3`,
/// `xD`, or a text arrow such as `->`) so the coordinator can replace it with its glyph, and
/// lets the very next Backspace undo the last conversion.
///
/// It is deliberately conservative: a wrong conversion in someone's text is far worse than a
/// missed one. Every rule below exists to keep false positives out:
/// - **Start point.** A candidate starts only when the previous input was a space, an opening
///   character `( [ { " '` or Return, after an idle gap longer than `idleGap`, or when there was
///   no previous input yet. So `http://`, `a:)`, `5:30` or `a->b` never match: the form must be
///   a word of its own. A reset (click, app switch, navigation key) is never a start point, since
///   the host text before the caret is then unknown, but an idle gap after it still is.
/// - **Inline code.** It never starts inside an inline code span (odd number of backticks since
///   the last Return), where `:)` or `->` are likely code.
/// - **Timing.** Each key of a candidate, the terminator included, must follow the previous one
///   within `keyWindow`: a slow sequence is more likely text being edited than a form typed in one go.
/// - **When it converts.** Only an exact table entry converts (exact case), and as soon as the
///   match is unambiguous:
///   - an entry that ends with a letter or digit (`:D`, `xD`, `<3`), or is listed in
///     `alwaysWaitsForTerminator` (`--`), waits for a terminator, so `:Da`, `xDog`, `<30` or
///     `--help` never convert;
///   - an entry that is a proper prefix of a longer entry (`<-` in `<->`, `<=` in `<=>`) waits
///     for the next key: a terminator, or any other key that breaks the longer form (`<--` gives
///     `←-`, `<=5` gives `≤5`), converts it;
///   - every other entry (`:)`, `->`, `>=`, `<->`) converts on its last key.
/// - **Terminators** are the space and `. , ! ? ; :`. They are swallowed by the coordinator and
///   typed again after the glyph. Return is not one: it cancels the candidate (re-posting a Return
///   would misfire in Enter-to-send apps) but is a start point for the next one.
struct EmoticonDetector: Sendable {
    enum Input: Sendable {
        case char(Character, at: Date)
        /// The space bar: a terminator, and a start point for the next candidate.
        case space(at: Date)
        /// Return or enter: cancels the candidate without converting, closes any inline code span
        /// and is a start point for the next candidate.
        case boundary(at: Date)
        /// Undoes the last conversion when it is the very next input (see `recordConversion`).
        case backspace(at: Date)
        /// Mouse click, app switch, modified key, navigation key, tab. Never a start point, but
        /// the idle gap is measured from it.
        case reset(at: Date)
    }

    /// One conversion, told to the coordinator, which swallows the key that completed it.
    struct Conversion: Equatable, Sendable {
        /// The glyph of the entry.
        let emoji: String
        /// The entry as typed, without the terminator (what an undo types back).
        let typed: String
        /// Characters to delete before typing `emitted`: the typed characters that reached the
        /// host. `typed.count - 1` for an entry that converts on its last key (that key is
        /// swallowed), `typed.count` for an entry that waits (the terminator is swallowed).
        let deleting: Int
        /// The text to type: `emoji`, plus the swallowed terminator or breaking key, if any.
        let emitted: String
    }

    enum Output: Equatable, Sendable {
        case none
        /// A valid prefix has just started (emitted once per candidate), so the coordinator can
        /// begin its background focus check before the conversion point arrives.
        case candidate
        case convert(Conversion)
        /// A Backspace right after a recorded conversion: delete `deleting` characters (the
        /// graphemes of `emitted`) and type `text` (the typed entry). The Backspace is swallowed.
        case revert(deleting: Int, text: String)
    }

    private enum Phase: Sendable {
        case idle
        /// `typed` is a proper prefix of an entry, or an entry that waits for its next key.
        case matching(typed: String)
    }

    /// What the previous input was, for the start rule.
    private enum PreviousInput: Sendable {
        /// Space, an opening character or Return: a candidate may start right after it.
        case startPoint
        /// Any other key, or a reset: only an idle gap allows a start.
        case other
    }

    /// FastMoji's own short list. Ambiguous forms that show up in normal text (`:/` in URLs,
    /// `8)` and `B)` in lists, `XD` as in "Adobe XD", `D:`, `:3`, `:x`) are left out on purpose.
    /// None is a proper prefix of another.
    static let emoticons: [String: String] = [
        ":)": "🙂",
        ":-)": "🙂",
        ":(": "🙁",
        ":-(": "🙁",
        ":D": "😃",
        ";)": "😉",
        ":P": "😛",
        "<3": "❤️",
        "</3": "💔",
        ":'(": "😢",
        ":O": "😮",
        "xD": "😆",
        ":|": "😐",
        "^^": "😊",
    ]

    /// Text arrows and symbols (opt-in: they also show up in code). `<-` and `<=` wait for the
    /// next key, since they start `<->` and `<=>`; `--` waits for a terminator (see
    /// `alwaysWaitsForTerminator`). `!=` is left out on purpose.
    static let arrows: [String: String] = [
        "->": "→",
        "=>": "⇒",
        "<-": "←",
        "<->": "↔",
        "<=>": "⇔",
        ">=": "≥",
        "<=": "≤",
        "--": "—",
    ]

    /// Toggles the inline code span; never part of an entry.
    private static let backtick: Character = "`"
    /// Typed right before a candidate, they keep it a word of its own: `(:)`, `"<3"`.
    private static let openingCharacters: Set<Character> = ["(", "[", "{", "\"", "'"]
    /// Convert a waiting entry and are typed again after the glyph (the space is its own input).
    private static let terminators: Set<Character> = [".", ",", "!", "?", ";", ":"]
    /// Entries that end with a symbol but still wait for a terminator: converting `--` on its
    /// second `-` would break `--help`, Markdown `---` and `-->`.
    private static let alwaysWaitsForTerminator: Set<String> = ["--"]

    private let entries: [String: String]
    /// Every non-empty proper prefix of an entry.
    private let prefixes: Set<String>
    /// Entries that end with a letter or digit, or listed in `alwaysWaitsForTerminator`: they
    /// convert only on a terminator. This rule wins over `waitsForLongerForm` if an entry matches both.
    private let waitsForTerminator: Set<String>
    /// Entries that are a proper prefix of a longer entry (`<-`): they convert on a terminator or
    /// on any key that breaks the longer form.
    private let waitsForLongerForm: Set<String>

    private let keyWindow: TimeInterval
    private let idleGap: TimeInterval
    private let revertWindow: TimeInterval

    private var phase: Phase = .idle
    /// nil only before the first input. No previous input counts as an idle gap, as in
    /// `TriggerDetector`.
    private var lastInputTime: Date?
    private var previous: PreviousInput = .other
    /// Odd number of backticks since the last Return. Kept across resets: a click does not
    /// tell us whether the caret left the code span, so stay disabled until the next Return.
    private var insideCodeSpan = false
    /// The last conversion the coordinator posted, and when; cleared by any input but Backspace.
    private var lastConversion: (conversion: Conversion, time: Date)?

    /// `entries` maps typed text to its glyph (`emoticons`, `arrows` or both). Entries of a single
    /// character never convert.
    init(
        entries: [String: String] = emoticons,
        keyWindow: TimeInterval = 1.0,
        idleGap: TimeInterval = 1.0,
        revertWindow: TimeInterval = 5.0
    ) {
        self.entries = entries
        self.keyWindow = keyWindow
        self.idleGap = idleGap
        self.revertWindow = revertWindow

        var prefixes = Set<String>()
        for key in entries.keys {
            var prefix = ""
            for char in key.dropLast() {
                prefix.append(char)
                prefixes.insert(prefix)
            }
        }
        let waitsForTerminator = Set(entries.keys.filter { key in
            Self.alwaysWaitsForTerminator.contains(key) || (key.last.map { $0.isLetter || $0.isNumber } ?? false)
        })
        self.prefixes = prefixes
        self.waitsForTerminator = waitsForTerminator
        self.waitsForLongerForm = Set(entries.keys.filter {
            prefixes.contains($0) && !waitsForTerminator.contains($0)
        })
    }

    /// Called by the coordinator once it has posted the keys of `conversion` (never when it let
    /// the key through), so a Backspace typed right after, within `revertWindow`, undoes it.
    mutating func recordConversion(_ conversion: Conversion, at time: Date) {
        lastConversion = (conversion, time)
    }

    mutating func feed(_ input: Input) -> Output {
        let recorded = lastConversion
        lastConversion = nil
        switch input {
        case .reset(let time):
            // Recorded so the idle gap that allows the next start is measured from the reset.
            record(time, previous: .other)
            phase = .idle
            return .none
        case .boundary(let time):
            defer { record(time, previous: .startPoint) }
            phase = .idle
            insideCodeSpan = false
            return .none
        case .space(let time):
            defer { record(time, previous: .startPoint) }
            return handleTerminator(" ", at: time)
        case .backspace(let time):
            // The deleted character is unknown, so the caret is not known to follow a start point.
            defer { record(time, previous: .other) }
            phase = .idle
            if let recorded, time.timeIntervalSince(recorded.time) < revertWindow {
                let conversion = recorded.conversion
                return .revert(deleting: conversion.emitted.count, text: conversion.typed)
            }
            return .none
        case .char(let char, let time):
            let output = handleChar(char, at: time)
            // A key swallowed by a conversion on its last key never reaches the host (`:(` leaves
            // 🙁, not `(`), so it is not a start point. A re-typed opening character `( [ { " '` is.
            var isOpening = Self.openingCharacters.contains(char)
            if case .convert(let conversion) = output, conversion.emitted == conversion.emoji {
                isOpening = false
            }
            record(time, previous: isOpening ? .startPoint : .other)
            return output
        }
    }

    /// Space or punctuation after a waiting entry: converts it, the terminator typed back after.
    private mutating func handleTerminator(_ terminator: Character, at time: Date) -> Output {
        guard case .matching(let typed) = phase else { return .none }
        phase = .idle
        guard isWithinWindow(time), let emoji = entries[typed] else { return .none }
        return convertWaiting(typed, emoji: emoji, followedBy: terminator)
    }

    private mutating func handleChar(_ char: Character, at time: Date) -> Output {
        if char == Self.backtick {
            insideCodeSpan.toggle()
            phase = .idle
            return .none
        }
        guard case .matching(let typed) = phase, isWithinWindow(time) else {
            // Too slow for the candidate: it is dropped, and the key may start a new one.
            phase = .idle
            return startIfPossible(char, at: time)
        }
        let next = typed + String(char)
        if let emoji = entries[next], !waits(next) {
            phase = .idle
            return .convert(Conversion(emoji: emoji, typed: next, deleting: next.count - 1, emitted: emoji))
        }
        if prefixes.contains(next) || entries[next] != nil {
            phase = .matching(typed: next)
            return .none
        }
        if Self.terminators.contains(char) {
            return handleTerminator(char, at: time)
        }
        phase = .idle
        if waitsForLongerForm.contains(typed), let emoji = entries[typed] {
            return convertWaiting(typed, emoji: emoji, followedBy: char)
        }
        // No restart on this key: the previous input was part of the candidate, so not a start point.
        return .none
    }

    private mutating func startIfPossible(_ char: Character, at time: Date) -> Output {
        let text = String(char)
        guard canStart(at: time), !insideCodeSpan, prefixes.contains(text) else { return .none }
        phase = .matching(typed: text)
        return .candidate
    }

    private func convertWaiting(_ typed: String, emoji: String, followedBy key: Character) -> Output {
        .convert(Conversion(emoji: emoji, typed: typed, deleting: typed.count, emitted: emoji + String(key)))
    }

    private func waits(_ entry: String) -> Bool {
        waitsForTerminator.contains(entry) || waitsForLongerForm.contains(entry)
    }

    private func canStart(at time: Date) -> Bool {
        guard let last = lastInputTime else { return true }
        return previous == .startPoint || time.timeIntervalSince(last) > idleGap
    }

    private func isWithinWindow(_ time: Date) -> Bool {
        guard let last = lastInputTime else { return false }
        return time.timeIntervalSince(last) < keyWindow
    }

    private mutating func record(_ time: Date, previous: PreviousInput) {
        lastInputTime = time
        self.previous = previous
    }
}
