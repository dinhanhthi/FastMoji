import Foundation
import Testing
@testable import FastMoji

struct EmoticonDetectorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test("` :) ` converts on the space terminator")
    func convertsAfterBoundaryAtTerminator() {
        var detector = EmoticonDetector()

        _ = detector.feed(.space(at: at(0)))
        _ = detector.feed(.char(":", at: at(0.05)))
        _ = detector.feed(.char(")", at: at(0.1)))
        let output = detector.feed(.space(at: at(0.15)))

        #expect(output == .convert(emoji: "🙂", typedLength: 2))
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
}
