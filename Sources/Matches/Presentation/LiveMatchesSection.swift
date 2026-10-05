import DesignSystem
import MatchesApplication
import SwiftUI

/// The hub's Live section (spec 009): oldest first, hidden when nothing is live.
public struct LiveMatchesSection: View {
    @Environment(\.matchesPorts) private var ports

    public init() {}

    public var body: some View {
        let rows = ports?.live.liveMatches ?? []
        if !rows.isEmpty {
            Section("Live") {
                ForEach(rows) { row in
                    NavigationLink(value: MatchRoute.live(row.id)) { LiveMatchRowView(row: row) }
                }
            }
        }
    }
}

struct LiveMatchRowView: View {
    let row: LiveMatchRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(row.sides) { side in
                    HStack {
                        PlayerPlate(name: side.name, colour: PlayerColour.color(side.colour))
                            .font(.headline)
                        Spacer(minLength: 8)
                        ScoreNumeral(side.frames)
                    }
                }
            }
            Divider()
            VStack(alignment: .trailing, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(clockText(row.matchTimer.elapsed(at: ctx.date)))
                        .monospacedDigit()
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(row.isPaused ? .secondary : .primary)
                }
                if row.isPaused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenScore(row.sides) + (row.isPaused ? ", paused" : ""))
        .accessibilityValue("Match time " + spokenDuration(row.matchTimer.elapsed(at: .now)))
    }
}
