import SwiftUI

/// Shared score numeral style (spec 022): monospaced digits that scale with Dynamic Type.
public enum ScoreSize: Sendable {
    /// Hub rows and lists.
    case row
    /// The live screen; must read from the rail, 1–3 m away.
    case hero
    /// The live scoreboard (spec 030): an exact size from `ScoreboardSizing`, never shrunk to fit, so a
    /// score keeps its size whatever its number of digits.
    case points(CGFloat)
}

public struct ScoreNumeral: View {
    let value: Int
    let size: ScoreSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 190

    public init(_ value: Int, size: ScoreSize = .row) {
        self.value = value
        self.size = size
    }

    public var body: some View {
        Text(value, format: .number)
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .lineLimit(1)
            .minimumScaleFactor(shrinks ? 0.5 : 1)
    }

    private var shrinks: Bool {
        if case .points = size { false } else { true }
    }

    private var font: Font {
        switch size {
        case .row: .title2.weight(.semibold)
        case .hero: .system(size: heroSize, weight: .bold, design: .rounded)
        case let .points(points): .system(size: points, weight: .bold, design: .rounded)
        }
    }
}
