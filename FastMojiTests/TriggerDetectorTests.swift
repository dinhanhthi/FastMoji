import Foundation
import Testing
@testable import FastMoji

struct TriggerDetectorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test("`std::vec` does not trigger")
    func identifierWithColonsDoesNotTrigger() {
        var detector = TriggerDetector()

        let outputs = Array("std::vec").enumerated().map { index, char in
            detector.feed(.char(char, at: at(Double(index) * 0.05)))
        }

        #expect(!outputs.contains(.open))
        #expect(!detector.isActive)
    }

    @Test("`::` after a space triggers and returns the query")
    func triggerAfterSpaceOpensWithQuery() {
        var detector = TriggerDetector()

        _ = detector.feed(.boundary(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        #expect(detector.feed(.char(":", at: at(0.1))) == .open)
        _ = detector.feed(.char("s", at: at(0.15)))
        _ = detector.feed(.char("m", at: at(0.2)))
        let output = detector.feed(.char("i", at: at(0.25)))

        #expect(output == .query("smi"))
        #expect(detector.typedLength == 5)
        #expect(detector.feed(.backspace(at: at(0.3))) == .query("sm"))
        #expect(detector.typedLength == 4)

        // Grows up to the cap; one more char closes, so a pick never deletes more.
        let maxTypedLength = "::".count + TriggerDetector.maxQueryLength
        for index in 2..<TriggerDetector.maxQueryLength {
            #expect(detector.feed(.char("a", at: at(0.35 + Double(index) * 0.05))) != .close)
            #expect(detector.typedLength <= maxTypedLength)
        }
        #expect(detector.query.count == TriggerDetector.maxQueryLength)
        #expect(detector.feed(.char("a", at: at(3))) == .close)
        #expect(detector.typedLength <= maxTypedLength)
    }

    @Test("slow `:` `:` (gap > keyWindow) does not trigger")
    func slowSequenceDoesNotTrigger() {
        var detector = TriggerDetector()

        _ = detector.feed(.boundary(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        let output = detector.feed(.char(":", at: at(0.5)))

        #expect(output == .none)
        #expect(!detector.isActive)
    }

    @Test("non-ASCII char in the query closes")
    func nonASCIICharCloses() {
        var detector = TriggerDetector()

        _ = detector.feed(.boundary(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        #expect(detector.feed(.char(":", at: at(0.1))) == .open)
        let output = detector.feed(.char("á", at: at(0.15)))

        #expect(output == .close)
        #expect(!detector.isActive)
    }
}
