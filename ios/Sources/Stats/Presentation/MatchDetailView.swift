import DesignSystem
import StatsApplication
import SwiftUI

/// Match detail (spec 013), from `MatchTimeline`: result, corrections beside the original score,
/// and per frame the winner, frame time, match time and running score. With `MatchDetailActions`
/// (spec 015): Edit corrects the score, and the menu marks an abandoned match finished or deletes it.
public struct MatchDetailView: View {
    let matchID: UUID
    @Environment(\.statsPorts) private var ports
    @Environment(\.matchDetailActions) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmMarkFinished = false
    @State private var confirmDelete = false
    @State private var error: String?

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
        .toolbar {
            if let actions { toolbar(t, actions) }
        }
        .sheet(isPresented: $editing) {
            if let actions {
                ScoreCorrectionSheet(timeline: t, correct: { try actions.correctScore(matchID, $0, $1) })
            }
        }
        .confirmationDialog("Mark this match finished?", isPresented: $confirmMarkFinished, titleVisibility: .visible) {
            Button("Mark Finished") { attempt($error) { try actions?.markFinished(matchID) } }
        } message: {
            Text("\(markFinishedOutcome(t.match)) It counts in stats from now on, and can't be abandoned again.")
        }
        .confirmationDialog("Delete this match?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Match", role: .destructive) {
                attempt($error) {
                    try actions?.delete(matchID)
                    dismiss()
                }
            }
        } message: {
            Text("\(HistoryFormat.spokenScore(t.match)) on \(HistoryFormat.dayAndTime(t.match.startedAt)) is removed from the history and stats. This can't be undone.")
        }
        .errorAlert($error)
    }

    @ToolbarContentBuilder
    private func toolbar(_ t: MatchTimeline, _ actions: MatchDetailActions) -> some ToolbarContent {
        // Cancelled matches can't be corrected (S29); only abandoned ones can be marked finished (S31).
        if t.match.status != .cancelled {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .accessibilityHint("Correct the score")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis.circle") {
                if t.match.status == .abandoned {
                    Button("Mark Finished", systemImage: "flag.checkered") { confirmMarkFinished = true }
                }
                Button("Delete Match", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
    }

    /// Winner as for finishing early: whoever is ahead; level is a draw (S31).
    private func markFinishedOutcome(_ m: PastMatchRow) -> String {
        let a = (m.score.firstSets ?? 0, m.score.first), b = (m.score.secondSets ?? 0, m.score.second)
        if a == b { return "It's level, so it becomes a draw." }
        return "\(a > b ? m.first.name : m.second.name) is ahead, so wins."
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

/// Timeline → Edit (S29): + and − per player and a box to type the whole score; for sets, each
/// set's frames separately. Refusals (race to off the target) show as errors; sets inconsistencies
/// are warnings to confirm or fix.
private struct ScoreCorrectionSheet: View {
    let timeline: MatchTimeline
    let correct: @MainActor (ScoreEdit, Bool) throws -> [String]
    @Environment(\.dismiss) private var dismiss
    /// One entry for a frames match; one per set for the sets style.
    @State private var scores: [ScorePair]
    @State private var typed = ""
    @State private var warnings: [String] = []
    @State private var error: String?

    init(timeline: MatchTimeline, correct: @escaping @MainActor (ScoreEdit, Bool) throws -> [String]) {
        self.timeline = timeline
        self.correct = correct
        _scores = State(initialValue: Self.current(timeline))
    }

    var body: some View {
        NavigationStack {
            Form {
                if timeline.isSets {
                    ForEach(scores.indices, id: \.self) { i in
                        Section("Set \(i + 1)") { steppers(i) }
                    }
                    Section {
                        Button("Add Set", systemImage: "plus") { scores.append(ScorePair(first: 0, second: 0)) }
                        if scores.count > 1 {
                            Button("Remove Last Set", systemImage: "minus", role: .destructive) { scores.removeLast() }
                        }
                    }
                } else {
                    Section { steppers(0) }
                    Section {
                        TextField("Type a score, e.g. 9–7", text: $typed)
                            .onSubmit(applyTyped)
                            .monospacedDigit()
                    } footer: {
                        Text("Added frames have no time; the timeline marks them as corrections.")
                    }
                }
            }
            .navigationTitle("Correct Score")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(confirmed: false) } }
            }
            .alert("Save this score?", isPresented: Binding(get: { !warnings.isEmpty }, set: { if !$0 { warnings = [] } })) {
                Button("Save Anyway") { save(confirmed: true) }
                Button("Fix It", role: .cancel) {}
            } message: {
                Text(warnings.joined(separator: "\n"))
            }
            .errorAlert($error)
        }
    }

    private func steppers(_ i: Int) -> some View {
        ForEach([true, false], id: \.self) { isFirst in
            let player = isFirst ? timeline.match.first : timeline.match.second
            let value = isFirst ? $scores[i].first : $scores[i].second
            Stepper(value: value, in: 0...999) {
                HStack {
                    PlayerPlate(name: player.name, colour: PlayerColour.color(player.colour), archived: player.isArchived)
                    Spacer()
                    Text(value.wrappedValue, format: .number).font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
            .accessibilityValue("\(player.name) \(value.wrappedValue)")
        }
    }

    /// "9–7", "9-7" or "9 7".
    private func applyTyped() {
        let numbers = typed.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 2 else { return }
        scores[0] = ScorePair(first: numbers[0], second: numbers[1])
        typed = ""
    }

    private func save(confirmed: Bool) {
        if !typed.isEmpty { applyTyped() }
        let edit: ScoreEdit = timeline.isSets ? .sets(scores) : .frames(scores[0])
        do {
            let needsConfirming = try correct(edit, confirmed)
            if needsConfirming.isEmpty { dismiss() } else { warnings = needsConfirming }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The score as it stands: frames, or each set's frames counted from the timeline.
    private static func current(_ t: MatchTimeline) -> [ScorePair] {
        guard t.isSets else { return [ScorePair(first: t.match.score.first, second: t.match.score.second)] }
        var sets: [ScorePair] = []
        for frame in t.frames {
            while sets.count < frame.setNumber { sets.append(ScorePair(first: 0, second: 0)) }
            if frame.winner.id == t.match.first.id { sets[frame.setNumber - 1].first += 1 } else { sets[frame.setNumber - 1].second += 1 }
        }
        return sets.isEmpty ? [ScorePair(first: 0, second: 0)] : sets
    }
}
