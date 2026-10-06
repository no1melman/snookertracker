import DesignSystem
import Foundation
import MatchesApplication
import SwiftUI

public extension View {
    /// The stale-match prompt (S28, spec 020): a sheet for each stale match in turn, until the queue
    /// is empty. It can't be swiped away; each match needs an answer. Nil shows nothing.
    func stalePrompt(_ queue: StaleMatchQueue?) -> some View {
        modifier(StalePromptModifier(queue: queue))
    }
}

struct StalePromptModifier: ViewModifier {
    let queue: StaleMatchQueue?

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { queue?.current }, set: { _ in })) { prompt in
            if let queue {
                StalePromptSheet(prompt: prompt, queue: queue)
                    .id(prompt.id)
                    .interactiveDismissDisabled()
            }
        }
    }
}

/// One stale match: players, score, how long it has been idle, both lengths side by side, and the
/// choices `ResolveStaleMatch` offers.
struct StalePromptSheet: View {
    let prompt: StaleMatchPrompt
    let queue: StaleMatchQueue
    @State private var endTime: Date
    @State private var confirming: LiveMatchView.EndAction?
    /// The end choice that was refused short of the target: ask before finishing anyway.
    @State private var finishAnyway: StaleChoice?
    @State private var error: String?

    init(prompt: StaleMatchPrompt, queue: StaleMatchQueue) {
        self.prompt = prompt
        self.queue = queue
        _endTime = State(initialValue: prompt.suggestedEndTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(prompt.sides) { side in
                        HStack {
                            PlayerPlate(name: side.name, colour: PlayerColour.color(side.colour))
                                .font(.headline)
                            Spacer(minLength: 8)
                            ScoreNumeral(side.frames)
                        }
                    }
                } footer: {
                    Text(Self.idleText(prompt))
                }

                Section {
                    LabeledContent("Ran", value: Self.duration(prompt.ranFor))
                    LabeledContent("Capped", value: Self.duration(prompt.cappedLength))
                } footer: {
                    Text(Self.cappedSource(prompt))
                }

                Section {
                    Button("Resume", systemImage: "play.fill") { choose(.resume) }
                }

                Section {
                    DatePicker("Ended at", selection: $endTime, in: prompt.earliestEndTime...prompt.latestEndTime)
                    Button("End at This Time", systemImage: "flag.checkered") { choose(.endAt(endTime)) }
                } footer: {
                    Text("Suggested: the last frame plus the usual frame time of whoever won it.")
                }

                Section {
                    Button("End with Capped Length", systemImage: "hourglass") { choose(.endCapped) }
                }

                if prompt.canAbandonOrCancel {
                    Section {
                        Button("Abandon", systemImage: "xmark.circle") { confirming = .abandon }
                        Button("Cancel Match", systemImage: "trash", role: .destructive) { confirming = .cancel }
                    }
                }
            }
            .navigationTitle("Still Playing?")
            .inlineTitle()
        }
        .confirmationDialog(confirming.map(LiveMatchView.endTitle) ?? "",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { action in
            Button(LiveMatchView.endButton(action), role: action == .cancel ? .destructive : nil) {
                choose(action == .cancel ? .cancel : .abandon)
            }
        } message: { action in
            Text(LiveMatchView.endMessage(action, frames: prompt.sides.map(\.frames)))
        }
        .alert("Nobody has reached the target", isPresented: Binding(get: { finishAnyway != nil }, set: { if !$0 { finishAnyway = nil } }),
               presenting: finishAnyway) { choice in
            Button("Finish Anyway") { choose(choice, anyway: true) }
            Button("Back", role: .cancel) {}
        } message: { _ in
            Text("Finishing now will count as abandoned.")
        }
        .errorAlert($error)
    }

    private func choose(_ choice: StaleChoice, anyway: Bool = false) {
        do {
            try queue.resolve(choice, anyway: anyway)
        } catch MatchCommandError.finishShortOfTarget {
            finishAnyway = choice
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Text

    static func idleText(_ p: StaleMatchPrompt) -> String {
        "Nothing has happened in this match for \(duration(p.idle))" + (p.isPaused ? ". It's paused." : ".")
    }

    /// "Fridays average for Asher and Callum", or the 3 h default.
    static func cappedSource(_ p: StaleMatchPrompt) -> String {
        guard p.cappedFromHistory else { return "No past matches between these two on this day: capped at 3 hours." }
        let symbols = Calendar.current.weekdaySymbols
        let day = symbols.indices.contains(p.weekday - 1) ? symbols[p.weekday - 1] + "s" : "This day"
        let names = p.sides.map(\.name).joined(separator: " and ")
        return "\(day) average for \(names)."
    }

    /// "1d 4h 2m", "2h 45m", "12m".
    static func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 3
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: max(60, seconds)) ?? ""
    }
}
