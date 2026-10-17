import Foundation

/// Pure state machine that recognises the inline trigger sequence (default `::`) in a key stream
/// and tracks the query typed after it.
struct TriggerDetector: Sendable {
    enum Input: Sendable {
        case char(Character, at: Date)
        /// Space, return or enter.
        case boundary(at: Date)
        case backspace(at: Date)
        /// Mouse click, app switch, modified key, navigation key, tab. Never a start point.
        case reset
    }

    enum Output: Equatable, Sendable {
        case none
        case open
        case query(String)
        case close
        /// The closing delimiter (last character of the sequence) typed after a non-empty query,
        /// e.g. `::smile:`. `typedLength` is the sequence plus the query: the delimiter itself is
        /// swallowed, never typed, so it is not counted.
        case delimiter(query: String, typedLength: Int)
    }

    private enum Phase: Sendable {
        case idle
        /// `matched` sequence characters have been typed so far.
        case matching(matched: Int)
        case active
    }

    /// Longest query kept. The longest alias in emoji.json is 53 characters
    /// (`persona_en_silla_de_ruedas_electrica_hacia_la_derecha`, es cldr); 64 leaves headroom.
    /// Longer closes, so a pick never deletes more than the sequence + 64.
    static let maxQueryLength = 64

    private let sequence: [Character]
    private let keyWindow: TimeInterval
    private let idleGap: TimeInterval

    private var phase: Phase = .idle
    /// nil only at start.
    private var lastInputTime: Date?
    private var lastWasBoundary = false

    private(set) var query = ""

    var isActive: Bool {
        if case .active = phase { return true }
        return false
    }

    /// Characters to delete on insert: the trigger sequence plus the query.
    var typedLength: Int { sequence.count + query.count }

    /// An empty `sequence` never triggers.
    init(sequence: String = "::", keyWindow: TimeInterval = 0.3, idleGap: TimeInterval = 1.0) {
        self.sequence = Array(sequence)
        self.keyWindow = keyWindow
        self.idleGap = idleGap
    }

    mutating func feed(_ input: Input) -> Output {
        switch input {
        case .reset:
            let wasActive = isActive
            enterIdle()
            // The host text before the caret is unknown: only a boundary or an idle gap starts.
            lastWasBoundary = false
            return wasActive ? .close : .none
        case .boundary(let time):
            defer { record(time, boundary: true) }
            let wasActive = isActive
            enterIdle()
            return wasActive ? .close : .none
        case .backspace(let time):
            defer { record(time, boundary: false) }
            return handleBackspace()
        case .char(let char, let time):
            defer { record(time, boundary: false) }
            return handleChar(char, at: time)
        }
    }

    private mutating func handleBackspace() -> Output {
        switch phase {
        case .active:
            if query.isEmpty {
                enterIdle()
                return .close
            }
            query.removeLast()
            return .query(query.lowercased())
        case .matching:
            enterIdle()
            return .none
        case .idle:
            return .none
        }
    }

    private mutating func handleChar(_ char: Character, at time: Date) -> Output {
        switch phase {
        case .active:
            if Self.isQueryCharacter(char), query.count < Self.maxQueryLength {
                query.append(char)
                return .query(query.lowercased())
            }
            // Never a query character (`AppSettings.isValidTriggerSequence`), so checked after.
            if char == sequence.last, !query.isEmpty {
                let output = Output.delimiter(query: query.lowercased(), typedLength: typedLength)
                enterIdle()
                return output
            }
            enterIdle()
            return .close
        case .matching(let matched):
            if char == sequence[matched], let last = lastInputTime,
               time.timeIntervalSince(last) <= keyWindow {
                return advance(to: matched + 1)
            }
            enterIdle()
            return startIfPossible(char, at: time)
        case .idle:
            return startIfPossible(char, at: time)
        }
    }

    private mutating func startIfPossible(_ char: Character, at time: Date) -> Output {
        guard char == sequence.first, canStart(at: time) else { return .none }
        return advance(to: 1)
    }

    private mutating func advance(to matched: Int) -> Output {
        if matched == sequence.count {
            phase = .active
            query = ""
            return .open
        }
        phase = .matching(matched: matched)
        return .none
    }

    private func canStart(at time: Date) -> Bool {
        guard let last = lastInputTime else { return true }
        return lastWasBoundary || time.timeIntervalSince(last) > idleGap
    }

    private mutating func enterIdle() {
        phase = .idle
        query = ""
    }

    private mutating func record(_ time: Date, boundary: Bool) {
        lastInputTime = time
        lastWasBoundary = boundary
    }

    /// Characters a query may contain; also never allowed in a trigger sequence.
    static func isQueryCharacter(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || char == "_" || char == "-" || char == "+")
    }
}
