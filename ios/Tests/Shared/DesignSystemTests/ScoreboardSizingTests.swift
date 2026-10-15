import CoreGraphics
import DesignSystem
import Testing

// The live scoreboard's sizing rules (spec 030): breaker emphasis, and a score size that never depends
// on the score.

@Suite struct ScoreboardSizingTests {
    private let portrait = (width: CGFloat(349), height: CGFloat(400))

    @Test func bothSidesAreEqualBeforeABreakerIsChosen() {
        let sizing = ScoreboardSizing(width: portrait.width, height: portrait.height, breaker: nil, cap: 190)
        #expect(sizing.widths[0] == sizing.widths[1])
        #expect(sizing.fontSizes[0] == sizing.fontSizes[1])
    }

    @Test(arguments: [0, 1])
    func theBreakersColumnAndScoreAreBigger(breaker: Int) {
        let sizing = ScoreboardSizing(width: portrait.width, height: portrait.height, breaker: breaker, cap: 190)
        let other = 1 - breaker
        #expect(sizing.widths[breaker] > sizing.widths[other])
        #expect(sizing.fontSizes[breaker] > sizing.fontSizes[other])
    }

    @Test func theEmphasisIsSlight() {
        let sizing = ScoreboardSizing(width: portrait.width, height: portrait.height, breaker: 0, cap: 190)
        let ratio = sizing.fontSizes[0] / sizing.fontSizes[1]
        #expect(ratio > 1.1 && ratio < 1.5)
    }

    @Test func theColumnsShareTheWidthWhoeverBreaks() {
        for breaker in [nil, 0, 1] {
            let sizing = ScoreboardSizing(width: portrait.width, height: portrait.height, breaker: breaker, cap: 190)
            #expect(abs(sizing.widths.reduce(0, +) - portrait.width) < 0.001)
        }
    }

    @Test(arguments: [nil, 0, 1])
    func everyScoreFitsTwoDigitsInItsColumn(breaker: Int?) {
        let sizing = ScoreboardSizing(width: portrait.width, height: portrait.height, breaker: breaker, cap: 1000)
        for i in 0..<2 {
            #expect(sizing.fontSizes[i] * 2 * ScoreboardSizing.digitWidth <= sizing.widths[i])
        }
    }

    @Test func theBreakersScoreFitsTheHeight() {
        let sizing = ScoreboardSizing(width: 2000, height: 200, breaker: 0, cap: 1000)
        #expect(sizing.fontSizes[0] * ScoreboardSizing.lineHeight <= 200 + 0.001)
    }

    @Test func theCapLimitsTheBaseSize() {
        let sizing = ScoreboardSizing(width: 2000, height: 2000, breaker: nil, cap: 190)
        #expect(sizing.fontSizes == [190, 190])
    }

    @Test func moreThanTwoSidesAreNeverEmphasised() {
        let sizing = ScoreboardSizing(width: 600, height: 400, breaker: 1, sides: 3, cap: 190)
        #expect(Set(sizing.widths).count == 1)
        #expect(Set(sizing.fontSizes).count == 1)
    }

    @Test func aTinySpaceGivesZeroNotNegativeSizes() {
        let sizing = ScoreboardSizing(width: -10, height: -10, breaker: 0, cap: 190)
        #expect(sizing.fontSizes.allSatisfy { $0 >= 0 })
        #expect(sizing.widths.allSatisfy { $0 >= 0 })
    }
}
