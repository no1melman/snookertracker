import DesignSystem
import StatsApplication
import SwiftUI

/// The monthly summary screen (spec 017, S38), from `MonthlySummary(series, month)`: "you" when Me
/// is in the series, otherwise each pairing; W–D–L, frames and deciders, and the change since the
/// previous month. Opens on last month (the one the notification is about) unless `month` is given;
/// the arrows step through months. Reached from a series row, or from the notification (019) by
/// pushing `MonthlySummaryView(series:month:)` with the published event's series and month.
public struct MonthlySummaryView: View {
    @Environment(\.seriesPorts) private var ports
    private let seriesID: UUID
    @State private var month: Date?

    /// `month`: any date inside the month to show; nil opens on last month.
    public init(series: UUID, month: Date? = nil) {
        seriesID = series
        _month = State(initialValue: month)
    }

    /// From `SeriesSummaryIssuedPublished`'s year and month (the notification).
    public init(series: UUID, year: Int, month: Int, calendar: Calendar = .current) {
        self.init(series: series, month: calendar.date(from: DateComponents(year: year, month: month, day: 1)))
    }

    public var body: some View {
        let query = ports?.summaries
        let shown = month ?? query?.lastMonth() ?? .now
        Group {
            if let query, let summary = query.summary(series: seriesID, monthOf: shown) {
                content(summary)
                    .navigationTitle(summary.seriesName)
                    .toolbar { stepper(summary) }
            } else {
                ContentUnavailableView("Series Not Found", systemImage: "square.stack.3d.up.slash",
                                       description: Text("This series has been deleted."))
            }
        }
        .inlineTitle()
    }

    @ViewBuilder private func content(_ summary: MonthlySummary) -> some View {
        if summary.isEmpty {
            ContentUnavailableView {
                Label("No Matches in \(summary.title)", systemImage: "calendar")
            } description: {
                Text("A summary appears for a month with at least one finished match of this series.")
            }
        } else {
            List {
                Section {
                    Text(summary.title).font(.title2.weight(.semibold))
                        .listRowBackground(Color.clear)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(summary.lines) { line in
                    Section {
                        SummaryLineCard(line: line)
                    } footer: {
                        Text(ChangeText.since(line.change, summary.previousMonthName))
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder private func stepper(_ summary: MonthlySummary) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Previous Month", systemImage: "chevron.left") { month = summary.previousMonthStart }
            Button("Next Month", systemImage: "chevron.right") { month = summary.nextMonthStart }
                .disabled(summary.nextMonthStart > .now)
        }
    }
}

/// One line: who, then W–D–L large, then frames and deciders.
struct SummaryLineCard: View {
    let line: MonthlySummaryLine

    var body: some View {
        let f = line.figures
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                switch line.subject {
                case .you(let me):
                    PlayerPlate(name: "You", colour: me.plateColour, archived: me.isArchived)
                case .pairing(let a, let b):
                    PlayerPlate(name: a.name, colour: a.plateColour, archived: a.isArchived)
                    Text("v").font(.subheadline).foregroundStyle(.secondary)
                    PlayerPlate(name: b.name, colour: b.plateColour, archived: b.isArchived)
                }
                Spacer(minLength: 8)
                Text(StatsFormat.percent(f.winPercentage))
                    .font(.headline).monospacedDigit()
                    .accessibilityLabel("Win rate \(StatsFormat.percent(f.winPercentage))")
            }
            .font(.body.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                result(f.won, "Won")
                if f.drawn > 0 { result(f.drawn, "Drawn") }
                result(f.lost, "Lost")
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                figure("Frames", StatsFormat.pair(f.framesWon, f.framesLost))
                figure("Deciders", StatsFormat.pair(f.decidersWon, f.decidersLost))
                if f.matchDecidersWon + f.matchDecidersLost > 0 {
                    figure("Match deciders", StatsFormat.pair(f.matchDecidersWon, f.matchDecidersLost))
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    private func result(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ScoreNumeral(value)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

enum ChangeText {
    /// "Since August: 2 more won, 1 fewer lost; frames +5–+2; win rate +15 pts." or
    /// "No matches in August to compare with."
    static func since(_ c: MonthlyChange, _ previous: String) -> String {
        if c.isFirstMonth { return "No matches in \(previous) to compare with." }
        var parts: [String] = []
        parts.append("won \(signed(c.won)), lost \(signed(c.lost))" + (c.drawn == 0 ? "" : ", drawn \(signed(c.drawn))"))
        parts.append("frames \(signed(c.framesWon))–\(signed(c.framesLost))")
        if c.decidersWon != 0 || c.decidersLost != 0 { parts.append("deciders \(signed(c.decidersWon))–\(signed(c.decidersLost))") }
        if let p = c.winPercentagePoints { parts.append("win rate \(signed(Int(p.rounded()))) pts") }
        return "Since \(previous): " + parts.joined(separator: "; ") + "."
    }

    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : n < 0 ? "\u{2212}\(-n)" : "±0" }
}
