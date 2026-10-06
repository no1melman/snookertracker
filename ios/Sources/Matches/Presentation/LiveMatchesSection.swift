import DesignSystem
import MatchesApplication
import SwiftUI

/// The hub's Live section (spec 009): oldest first, hidden when nothing is live. Swipe a row to
/// Finish or Abandon it without opening it (spec 015), with the live screen's confirmations.
public struct LiveMatchesSection: View {
    @Environment(\.matchesPorts) private var ports
    @State private var ending: Ending?
    /// Set when Finish was refused short of the target: ask before finishing anyway.
    @State private var finishAnyway: LiveMatchRow?
    @State private var error: String?

    private struct Ending: Identifiable {
        let row: LiveMatchRow
        let action: LiveMatchView.EndAction
        var id: String { "\(row.id)-\(action.rawValue)" }
    }

    public init() {}

    public var body: some View {
        let rows = ports?.live.liveMatches ?? []
        if !rows.isEmpty {
            Section("Live") {
                ForEach(rows) { row in
                    NavigationLink(value: MatchRoute.live(row.id)) { LiveMatchRowView(row: row) }
                        .swipeActions {
                            Button("Finish", systemImage: "flag.checkered") { ending = Ending(row: row, action: .finish) }
                                .tint(.green)
                                .labelStyle(.iconOnly)
                            Button("Abandon", systemImage: "xmark.circle") { ending = Ending(row: row, action: .abandon) }
                                .tint(.orange)
                                .labelStyle(.iconOnly)
                        }
                }
            }
            .confirmationDialog(ending.map { LiveMatchView.endTitle($0.action) } ?? "",
                                isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
                                titleVisibility: .visible, presenting: ending) { ending in
                Button(LiveMatchView.endButton(ending.action)) { end(ending.row, ending.action) }
            } message: { ending in
                Text(LiveMatchView.endMessage(ending.action, frames: ending.row.sides.map(\.frames)))
            }
            .alert("Nobody has reached the target", isPresented: Binding(get: { finishAnyway != nil }, set: { if !$0 { finishAnyway = nil } }),
                   presenting: finishAnyway) { row in
                Button("Finish Anyway") { end(row, .finish, anyway: true) }
                Button("Keep Playing", role: .cancel) {}
            } message: { _ in
                Text("Finishing now will count as abandoned.")
            }
            .errorAlert($error)
        }
    }

    private func end(_ row: LiveMatchRow, _ action: LiveMatchView.EndAction, anyway: Bool = false) {
        guard let commands = ports?.commands else { return }
        do {
            switch action {
            case .finish: try commands.finishMatch(row.id, anyway: anyway)
            case .abandon: try commands.abandonMatch(row.id)
            case .cancel: try commands.cancelMatch(row.id)
            }
        } catch MatchCommandError.finishShortOfTarget {
            finishAnyway = row
        } catch {
            self.error = error.localizedDescription
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
