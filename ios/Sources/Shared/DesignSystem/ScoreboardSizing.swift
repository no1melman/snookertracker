import CoreGraphics

/// Sizes the live screen's two score columns (spec 030). The breaker's column and score are a little
/// bigger; the score size never depends on how many digits a score has, so 10 is as big as 9. Pure, so
/// the rules are tested without rendering.
public struct ScoreboardSizing: Equatable, Sendable {
    /// How much wider the breaker's column is than an even split, as a fraction of it (0.12 → 56 / 44).
    public static let emphasis: CGFloat = 0.12
    /// The width of one hero digit as a fraction of the font size (SF Rounded bold, monospaced digits).
    public static let digitWidth: CGFloat = 0.62
    /// A text line is about this many times the font size tall.
    public static let lineHeight: CGFloat = 1.2

    /// Column widths, in the order of the sides.
    public let widths: [CGFloat]
    /// Score font sizes, in the order of the sides.
    public let fontSizes: [CGFloat]

    /// - Parameters:
    ///   - width: the width shared by the score columns, spacing excluded
    ///   - height: the height a score may take up
    ///   - breaker: the index of the breaking side, nil before a breaker is chosen
    ///   - sides: the number of sides; emphasis applies only to two
    ///   - cap: the largest base font size (the Dynamic Type hero size)
    public init(width: CGFloat, height: CGFloat, breaker: Int?, sides: Int = 2, cap: CGFloat) {
        let count = max(sides, 1)
        let even = max(width, 0) / CGFloat(count)
        let factors: [CGFloat] = (0..<count).map { i in
            guard count == 2, let breaker else { return 1 }
            return i == breaker ? 1 + Self.emphasis : 1 - Self.emphasis
        }
        // Always sized for two digits: frame counts run to about 30 (spec 022), and a score must not
        // shrink when it reaches 10. The base fits the even split; the emphasis scales width and size alike.
        let fitsWidth = even / (2 * Self.digitWidth + 0.1)
        let fitsHeight = max(height, 0) / (Self.lineHeight * (1 + Self.emphasis))
        let base = max(min(fitsWidth, fitsHeight, cap), 0)
        widths = factors.map { even * $0 }
        fontSizes = factors.map { base * $0 }
    }
}
