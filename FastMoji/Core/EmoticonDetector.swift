import Foundation

/// Pure state machine that recognises a classic text emoticon (`:)`, `<3`, `xD`...) typed as a
/// whole word and finished with a space, so the coordinator can replace it with an emoji.
///
/// It is deliberately conservative: a wrong conversion in someone's text is far worse than a
/// missed one. Every rule below exists to keep false positives out:
/// - A candidate starts only right after an explicit space or Return, so `http://`, `a:)`,
///   `5:30` or `f(x)` never match: the emoticon must be a word of its own.
/// - It never starts after a reset or at the very start, because the host text before the
///   caret is then unknown (a click may have put the caret inside a word).
/// - It never starts inside an inline code span (odd number of backticks since the last Return),
///   where `:)` or `<3` are likely code.
/// - It converts only when the typed text exactly equals a table entry and is followed by a
///   space, so `Bobby`, `xDog`, `:Pa` or `<3D` never convert.
struct EmoticonDetector: Sendable {
    enum Input: Sendable {
        case char(Character, at: Date)
        /// The space bar: the only terminator, and a left boundary for the next candidate.
        case space(at: Date)
        /// Return or enter: a left boundary that cancels the candidate without converting and
        /// closes any inline code span.
        case boundary(at: Date)
        case backspace(at: Date)
        /// Mouse click, app switch, modified key, navigation key, tab. Never a start point.
        case reset
    }

    enum Output: Equatable, Sendable {
        case none
        /// A valid emoticon prefix has just started (emitted once per candidate), so the
        /// coordinator can begin its background focus check before the terminator arrives.
        case candidate
        /// The space terminator after an exact table entry. `typedLength` is the emoticon only:
        /// the space is swallowed by the coordinator and re-typed after the emoji.
        case convert(emoji: String, typedLength: Int)
    }

    private enum Phase: Sendable {
        case idle
        /// `typed` is a prefix of at least one table entry.
        case matching(typed: String)
    }

    /// FastMoji's own short list. Ambiguous forms that show up in normal text (`:/` in URLs,
    /// `8)` and `B)` in lists, `XD` as in "Adobe XD", `D:`, `:3`, `:x`) are left out on purpose.
    /// Exact case only.
    static let table: [String: String] = [
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

    /// Toggles the inline code span; never part of an emoticon.
    private static let backtick: Character = "`"

    /// Maximum gap between two keys of one emoticon, including the space terminator. A slow
    /// sequence is more likely ordinary text being edited than an emoticon typed in one go.
    private let keyWindow: TimeInterval

    private var phase: Phase = .idle
    /// nil only at start.
    private var lastInputTime: Date?
    /// The previous input was a space or Return. A reset clears it: the text before the caret
    /// is unknown afterwards.
    private var lastWasBoundary = false
    /// Odd number of backticks since the last Return. Kept across resets: a click does not
    /// tell us whether the caret left the code span, so stay disabled until the next Return.
    private var insideCodeSpan = false

    init(keyWindow: TimeInterval = 1.0) {
        self.keyWindow = keyWindow
    }

    mutating func feed(_ input: Input) -> Output {
        switch input {
        case .reset:
            phase = .idle
            lastWasBoundary = false
            return .none
        case .boundary(let time):
            defer { record(time, boundary: true) }
            phase = .idle
            insideCodeSpan = false
            return .none
        case .space(let time):
            defer { record(time, boundary: true) }
            return handleSpace(at: time)
        case .backspace(let time):
            // The deleted character is unknown, so the caret is not known to follow a boundary.
            defer { record(time, boundary: false) }
            phase = .idle
            return .none
        case .char(let char, let time):
            defer { record(time, boundary: false) }
            return handleChar(char, at: time)
        }
    }

    private mutating func handleSpace(at time: Date) -> Output {
        guard case .matching(let typed) = phase else { return .none }
        phase = .idle
        guard isWithinWindow(time), let emoji = Self.table[typed] else { return .none }
        return .convert(emoji: emoji, typedLength: typed.count)
    }

    private mutating func handleChar(_ char: Character, at time: Date) -> Output {
        if char == Self.backtick {
            insideCodeSpan.toggle()
            phase = .idle
            return .none
        }
        switch phase {
        case .matching(let typed):
            let next = typed + String(char)
            if isWithinWindow(time), Self.isPrefix(next) {
                phase = .matching(typed: next)
            } else {
                // No restart on this character: the previous input was not a boundary.
                phase = .idle
            }
            return .none
        case .idle:
            // The gap since the space is not limited: a pause before starting the emoticon
            // ("Great job " ... ":)") is common, and any caret move in between sends a reset.
            guard lastWasBoundary, !insideCodeSpan, Self.isPrefix(String(char)) else {
                return .none
            }
            phase = .matching(typed: String(char))
            return .candidate
        }
    }

    private func isWithinWindow(_ time: Date) -> Bool {
        guard let last = lastInputTime else { return false }
        return time.timeIntervalSince(last) < keyWindow
    }

    private mutating func record(_ time: Date, boundary: Bool) {
        lastInputTime = time
        lastWasBoundary = boundary
    }

    private static func isPrefix(_ text: String) -> Bool {
        table.keys.contains { $0.hasPrefix(text) }
    }
}
