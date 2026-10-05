import DesignSystem
import StatsApplication
import SwiftUI

/// Match detail (spec 013), from `MatchTimeline`: result, corrections beside the original score,
/// and per frame the winner, frame time, match time and running score.
public struct MatchDetailView: View {
    let matchID: UUID
    @Environment(\.statsPorts) private var ports

    public init(matchID: UUID) {
        self.matchID = matchID
    }

    public var body: some View {
        Group {
            if let timeline = ports?.history.timeline(matchID) {
                content(timeline)
            } else {
                ContentUnavailableView("Match not found", systemImage: "questionmark.circle",
                                       description: Text("It may have been deleted."))
            }
        }
        .inlineTitle()
    }

    private func content(_ t: MatchTimeline) -> some View {
        List {
            Section { header(t) }
            if !t.corrections.isEmpty || t.markedFinishedAt != nil {
                Section("Alterations") { alterations(t) }
            }
            Section("Details") {
                LabeledContent("Started", value: t.match.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let ended = t.match.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .omitted, time: .shortened))
                }
                if let length = t.match.length {
                    LabeledContent("Length") { Text(clockText(length)).monospacedDigit() }
                }
                LabeledContent("Game", value: HistoryFormat.game(t.match.game))
                LabeledContent("Style", value: t.match.style)
                LabeledContent("Break", value: HistoryFormat.breakRule(t.breakRule))
            }
            if t.frames.isEmpty {
                Section("Frames") {
                    Text("No frames were played.").foregroundStyle(.secondary)
                }
            } else if t.isSets {
                ForEach(sets(t.frames), id: \.0) { set, frames in
                    Section("Set \(set)") { ForEach(frames) { FrameRow(frame: $0, isSets: true) } }
                }
            } else {
                Section {
                    ForEach(t.frames) { FrameRow(frame: $0, isSets: false) }
                } header: {
                    FrameColumnsHeader()
                }
            }
        }
        .navigationTitle(HistoryFormat.dayAndTime(t.match.startedAt))
    }

    private func header(_ t: MatchTimeline) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                sideColumn(t.match.first, t.match.score.first, t.match.score.firstSets, t)
                Text("–").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                sideColumn(t.match.second, t.match.score.second, t.match.score.secondSets, t)
            }
            if t.match.score.firstSets != nil {
                Text("Frames \(t.match.score.first)–\(t.match.score.second)")
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let result = resultText(t.match) { Text(result).font(.subheadline.weight(.semibold)) }
                StatusBadges(row: t.match)
            }
            if let original = t.originalScore, original != t.match.score {
                Text("Originally \(original.text)")
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func sideColumn(_ p: HistoryPlayer, _ frames: Int, _ sets: Int?, _ t: MatchTimeline) -> some View {
        VStack(spacing: 6) {
            Text((sets ?? frames), format: .number)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(t.match.winner == nil || t.match.winner == p.id ? .primary : .secondary)
            PlayerPlate(name: p.name, colour: PlayerColour.color(p.colour), archived: p.isArchived)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
    }

    /// The winner; draws, abandoned and cancelled matches are said by their badge.
    private func resultText(_ m: PastMatchRow) -> String? {
        guard let w = m.winner else { return nil }
        return "\(w == m.first.id ? m.first.name : m.second.name) won"
    }

    @ViewBuilder
    private func alterations(_ t: MatchTimeline) -> some View {
        ForEach(Array(t.corrections.enumerated()), id: \.offset) { _, c in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(c.before.text).strikethrough().foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(c.after.text).fontWeight(.semibold)
                }
                .monospacedDigit()
                Text("Score corrected \(c.at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score corrected from \(c.before.text) to \(c.after.text)")
        }
        if let marked = t.markedFinishedAt {
            VStack(alignment: .leading, spacing: 2) {
                Text("Abandoned, then marked finished").fontWeight(.semibold)
                Text(marked.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func sets(_ frames: [MatchTimeline.FrameEntry]) -> [(Int, [MatchTimeline.FrameEntry])] {
        var result: [(Int, [MatchTimeline.FrameEntry])] = []
        for f in frames {
            if result.last?.0 == f.setNumber { result[result.count - 1].1.append(f) } else { result.append((f.setNumber, [f])) }
        }
        return result
    }
}

private struct FrameColumnsHeader: View {
    var body: some View {
        HStack {
            Text("Frames")
            Spacer()
            Text("Score")
        }
    }
}

/// One frame: number, winner, frame time, match time then, running score.
private struct FrameRow: View {
    let frame: MatchTimeline.FrameEntry
    let isSets: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(frame.number)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                PlayerPlate(name: frame.winner.name, colour: PlayerColour.color(frame.winner.colour), archived: frame.winner.isArchived)
                    .font(.body.weight(.medium))
                Text("\(clockText(frame.frameTime)) frame · at \(clockText(frame.matchTime))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(frame.runningScore.first)–\(frame.runningScore.second)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if isSets, let a = frame.runningScore.firstSets, let b = frame.runningScore.secondSets {
                    Text(frame.wonSet ? "Set won · \(a)–\(b)" : "Sets \(a)–\(b)")
                        .font(.caption.weight(frame.wonSet ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(frame.wonSet ? .primary : .secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Frame \(frame.number), \(frame.winner.name) won in \(spokenDuration(frame.frameTime)), "
            + "match time \(spokenDuration(frame.matchTime)), score \(frame.runningScore.first) \(frame.runningScore.second)")
    }
}
