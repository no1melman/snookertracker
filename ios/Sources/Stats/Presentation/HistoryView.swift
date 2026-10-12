import DesignSystem
import StatsApplication
import UpgradePublished
import SwiftUI

/// History (spec 013): ended matches from `PastMatches`, newest first, grouped by month. Rows push
/// `StatsRoute.match`; the host registers its destination (`MatchDetailView`).
public struct HistoryView: View {
    @Environment(\.statsPorts) private var ports
    @AppStorage("history.showCancelled") private var showCancelled = false
    @AppStorage("history.includeArchived") private var includeArchived = false
    @State private var deleting: PastMatchRow?
    @State private var error: String?

    public init() {}

    private var filter: PastMatchesFilter {
        PastMatchesFilter(showCancelled: showCancelled, includeArchivedPlayers: includeArchived)
    }

    public var body: some View {
        let rows = ports?.history.pastMatches(filter) ?? []
        let hidden = ports?.history.hiddenMatchCount(filter) ?? 0
        Group {
            if rows.isEmpty && hidden == 0 {
                emptyState
            } else {
                List {
                    if rows.isEmpty {
                        Text("None of the matches you can see match this filter.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(months(rows), id: \.title) { month in
                        Section(month.title) {
                            ForEach(month.rows) { row in
                                NavigationLink(value: StatsRoute.match(row.id)) { PastMatchRowView(row: row) }
                                    .swipeActions {
                                        if ports?.deleteMatch != nil {
                                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = row }
                                                .labelStyle(.iconOnly)
                                        }
                                    }
                            }
                        }
                    }
                    if hidden > 0 {
                        Section { HiddenMatchesRow(count: hidden) { ports?.showUpgradeOffer(.fullHistory) } }
                    }
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete this match?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { row in
            Button("Delete Match", role: .destructive) {
                attempt($error) { try ports?.deleteMatch?(row.id) }
            }
        } message: { row in
            Text("\(HistoryFormat.spokenScore(row)) on \(HistoryFormat.dayAndTime(row.startedAt)) is removed from the history and stats. This can't be undone.")
        }
        .errorAlert($error)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Show Cancelled", isOn: $showCancelled)
                    Toggle("Include Archived Players", isOn: $includeArchived)
                } label: {
                    Label("Filter", systemImage: isFiltered
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var isFiltered: Bool { showCancelled || includeArchived }

    @ViewBuilder private var emptyState: some View {
        let anyAtAll = !(ports?.history.pastMatches(PastMatchesFilter(showCancelled: true, includeArchivedPlayers: true)) ?? []).isEmpty
        if anyAtAll {
            ContentUnavailableView(
                "No Matches Shown", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Matches with archived players, or cancelled ones, are hidden. Change the filter to see them."))
        } else {
            ContentUnavailableView(
                "No History Yet", systemImage: "clock.arrow.circlepath",
                description: Text("Matches you finish or abandon appear here, newest first."))
        }
    }

    private struct Month { let title: String; var rows: [PastMatchRow] }

    private func months(_ rows: [PastMatchRow]) -> [Month] {
        var result: [Month] = []
        for row in rows {
            let title = HistoryFormat.month(row.startedAt)
            if result.last?.title == title { result[result.count - 1].rows.append(row) } else { result.append(Month(title: title, rows: [row])) }
        }
        return result
    }
}

/// A History row: day and time, colour plates and names, score, style, and status labels.
struct PastMatchRowView: View {
    let row: PastMatchRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(HistoryFormat.dayAndTime(row.startedAt))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                if let length = row.length {
                    Label(clockText(length), systemImage: "timer")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    side(row.first, frames: row.score.first, sets: row.score.firstSets)
                    side(row.second, frames: row.score.second, sets: row.score.secondSets)
                }
            }
            HStack(spacing: 6) {
                Text("\(HistoryFormat.game(row.game)) · \(row.style)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusBadges(row: row)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func side(_ player: HistoryPlayer, frames: Int, sets: Int?) -> some View {
        let won = row.winner == player.id
        return HStack {
            PlayerPlate(name: player.name, colour: PlayerColour.color(player.colour), archived: player.isArchived)
                .font(.headline.weight(won ? .bold : .regular))
            if won {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if let sets {
                Text("(\(frames))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                ScoreNumeral(sets)
            } else {
                ScoreNumeral(frames)
                    .foregroundStyle(won || row.winner == nil ? .primary : .secondary)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [HistoryFormat.dayAndTime(row.startedAt), HistoryFormat.spokenScore(row)]
        if let w = row.winner { parts.append("\(w == row.first.id ? row.first.name : row.second.name) won") }
        if row.isDraw { parts.append("Draw") }
        if row.status == .abandoned { parts.append("Abandoned") }
        if row.status == .cancelled { parts.append("Cancelled") }
        if row.isAltered { parts.append("Altered") }
        parts.append(row.style)
        if let length = row.length { parts.append("Length " + spokenDuration(length)) }
        return parts.joined(separator: ", ")
    }
}

/// Abandoned / Cancelled / Draw / Altered labels.
struct StatusBadges: View {
    let row: PastMatchRow

    var body: some View {
        HStack(spacing: 4) {
            if row.status == .abandoned { badge("Abandoned", .orange) }
            if row.status == .cancelled { badge("Cancelled", .secondary) }
            if row.isDraw { badge("Draw", .secondary) }
            if row.isAltered { badge("Altered", .purple) }
        }
    }

    private func badge(_ text: String, _ style: some ShapeStyle) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(style)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().strokeBorder(style, lineWidth: 1))
    }
}
