import SwiftUI

/// Shared score numeral style (spec 022): monospaced digits that scale with Dynamic Type.
public enum ScoreSize: Sendable {
    /// Hub rows and lists.
    case row
    /// The live screen; must read from the rail, 1–3 m away.
    case hero
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
            .minimumScaleFactor(0.5)
    }

    private var font: Font {
        switch size {
        case .row: .title2.weight(.semibold)
        case .hero: .system(size: heroSize, weight: .bold, design: .rounded)
        }
    }
}

#Preview {
    HStack(spacing: 40) {
        ScoreNumeral(4, size: .hero)
        ScoreNumeral(3, size: .hero)
    }
}
