import Foundation
import Testing
@testable import FastMoji

struct EmoticonDetectorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test("` :)` converts on the `)`")
    func convertsAfterBoundaryOnLastKey() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        let output = detector.feed(.char(")", at: at(0.1)))

        #expect(output == .convert(.init(emoji: "🙂", typed: ":)", deleting: 1, emitted: "🙂")))
    }

    @Test("`a:) ` without a left boundary does not convert")
    func noConversionWithoutLeftBoundary() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        let outputs = [
            detector.feed(.char("a", at: at(0.05))),
            detector.feed(.char(":", at: at(0.1))),
            detector.feed(.char(")", at: at(0.15))),
            detector.feed(.space(at: at(0.2))),
        ]

        #expect(outputs.allSatisfy { $0 == .none })
    }

    @Test("` :` then `)` after a pause over keyWindow does not convert")
    func noConversionAfterPause() {
        var detector = EmoticonDetector(keyWindow: 1.0)

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        _ = detector.feed(.char(")", at: at(1.25)))
        let output = detector.feed(.space(at: at(1.3)))

        #expect(output == .none)
    }

    @Test("` :D,` converts on the `,`, which is typed back after the emoji")
    func letterEndingFormConvertsOnTerminator() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        let waiting = detector.feed(.char("D", at: at(0.1)))
        let output = detector.feed(.char(",", at: at(0.15)))

        #expect(waiting == .none)
        #expect(output == .convert(.init(emoji: "😃", typed: ":D", deleting: 2, emitted: "😃,")))
    }

    @Test("` :D` followed by Return does not convert")
    func letterEndingFormCancelledByReturn() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        _ = detector.feed(.char("D", at: at(0.1)))
        let outputs = [
            detector.feed(.boundary(at: at(0.15))),
            detector.feed(.space(at: at(0.2))),
        ]

        #expect(outputs.allSatisfy { $0 == .none })
    }

    @Test("` <-` then `>` converts to the longer arrow")
    func arrowPrefixWaitsForLongerForm() {
        var detector = EmoticonDetector(entries: EmoticonDetector.arrows)

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char("<", at: at(0.05)))
        let waiting = detector.feed(.char("-", at: at(0.1)))
        let output = detector.feed(.char(">", at: at(0.15)))

        #expect(waiting == .none)
        #expect(output == .convert(.init(emoji: "↔", typed: "<->", deleting: 2, emitted: "↔")))
    }

    @Test("` <-` then a space converts to the left arrow, the space typed back")
    func arrowPrefixConvertsOnSpace() {
        var detector = EmoticonDetector(entries: EmoticonDetector.arrows)

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char("<", at: at(0.05)))
        _ = detector.feed(.char("-", at: at(0.1)))
        let output = detector.feed(.space(at: at(0.15)))

        #expect(output == .convert(.init(emoji: "←", typed: "<-", deleting: 2, emitted: "← ")))
    }

    @Test("Backspace right after a recorded conversion reverts it")
    func backspaceRevertsLastConversion() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        guard case .convert(let conversion) = detector.feed(.char(")", at: at(0.1))) else {
            Issue.record("` :)` did not convert")
            return
        }
        detector.recordConversion(conversion, at: at(0.1))
        let output = detector.feed(.backspace(at: at(0.5)))

        #expect(output == .revert(deleting: 1, text: ":)"))
    }

    @Test("Backspace after another input does not revert the conversion")
    func backspaceAfterOtherInputDoesNotRevert() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        guard case .convert(let conversion) = detector.feed(.char(")", at: at(0.1))) else {
            Issue.record("` :)` did not convert")
            return
        }
        detector.recordConversion(conversion, at: at(0.1))
        _ = detector.feed(.space(at: at(0.3)))
        let output = detector.feed(.backspace(at: at(0.5)))

        #expect(output == .none)
    }

    @Test("`(:)` converts after the opening character; after a reset, only an idle gap allows a start")
    func startRuleOpeningCharacterAndReset() {
        var detector = EmoticonDetector(keyWindow: 1.0, idleGap: 1.0)
        let smile = EmoticonDetector.Output.convert(.init(emoji: "🙂", typed: ":)", deleting: 1, emitted: "🙂"))

        _ = detector.feed(.char("a", at: at(0)))
        _ = detector.feed(.char("(", at: at(0.05)))
        _ = detector.feed(.char(":", at: at(0.1)))
        #expect(detector.feed(.char(")", at: at(0.15))) == smile)

        // Long after the last typed key, but right after a reset (e.g. arrow keys): no start.
        _ = detector.feed(.reset(at: at(5)))
        _ = detector.feed(.char(":", at: at(5.05)))
        #expect(detector.feed(.char(")", at: at(5.1))) == .none)

        // An idle gap over idleGap after the reset: a start point.
        _ = detector.feed(.reset(at: at(10)))
        _ = detector.feed(.char(":", at: at(11.5)))
        #expect(detector.feed(.char(")", at: at(11.55))) == smile)
    }
}
