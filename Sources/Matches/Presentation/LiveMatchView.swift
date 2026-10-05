import DesignSystem
import MatchesApplication
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The live screen (specs 009, 010): two player columns, huge scores, + / −, timers, pause, end.
public struct LiveMatchView: View {
    let matchID: MatchID
    @Environment(\.matchesPorts) private var ports
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var ending: EndAction?
    /// Set when Finish was refused short of the target: ask before finishing anyway.
    @State private var finishAnyway = false

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    enum EndAction: String, Identifiable {
        case finish, abandon, cancel
        var id: String { rawValue }
    }

    public var body: some View {
        Group {
            if let ports, let screen = ports.screens.liveMatchScreen(matchID) {
                content(screen, ports.commands)
            } else {
                ContentUnavailableView("Match ended", systemImage: "flag.checkered")
            }
        }
        .errorAlert($error)
        .onAppear { keepAwake(true) }
        .onDisappear { keepAwake(false) }
    }

    @ViewBuilder
    private func content(_ screen: LiveMatchScreen, _ commands: any MatchCommands) -> some View {
        VStack(spacing: 0) {
            header(screen)
            HStack(alignment: .top, spacing: 12) {
                ForEach(screen.sides) { side in
                    PlayerColumn(side: side, screen: screen, error: $error)
                }
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)
            if screen.isPaused { pausedBar(commands) }
        }
        .navigationTitle(screen.style.title)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if screen.isPaused {
                    Button("Resume", systemImage: "play.fill") { attempt($error) { try commands.resumeMatch(matchID) } }
                } else {
                    Button("Pause", systemImage: "pause.fill") { attempt($error) { try commands.pauseMatch(matchID) } }
                        .disabled(!screen.controls.pause)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Finish Match", systemImage: "flag.checkered") { ending = .finish }
                    Button("Abandon Match", systemImage: "xmark.circle") { ending = .abandon }
                    Button("Cancel Match", systemImage: "trash", role: .destructive) { ending = .cancel }
                }
            }
        }
        .confirmationDialog(endTitle(screen), isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }), titleVisibility: .visible, presenting: ending) { action in
            Button(endButton(action), role: action == .cancel ? .destructive : nil) { end(action, commands) }
        } message: { action in
            Text(endMessage(action, screen))
        }
        .alert("Nobody has reached the target", isPresented: $finishAnyway) {
            Button("Finish Anyway") { end(.finish, commands, anyway: true) }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Finishing now will count as abandoned.")
        }
        .alert(targetTitle(screen), isPresented: .constant(screen.targetReachedBy != nil && ending == nil && !finishAnyway)) {
            Button("Finish Match") { end(.finish, commands) }
            Button("Undo Last Frame", role: .cancel) {
                if let p = screen.targetReachedBy { attempt($error) { try commands.removeFrame(matchID, from: p) } }
            }
        } message: {
            Text("\(screen.sides.map { "\($0.name) \($0.frames)" }.joined(separator: " – ")). Undo if the frame was a mis-tap.")
        }
    }

    private func header(_ screen: LiveMatchScreen) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Frame \(screen.frameNumber)")
                        .font(.headline)
                    Text(clockText(screen.frameTimer.elapsed(at: ctx.date)))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(screen.isPaused ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text("Match \(clockText(screen.matchTimer.elapsed(at: ctx.date)))").monospacedDigit()
                    Text("·")
                    Text(screen.game.title)
                    Text("·")
                    Text(screen.startedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Frame \(screen.frameNumber), \(spokenDuration(screen.frameTimer.elapsed(at: ctx.date))). Match time \(spokenDuration(screen.matchTimer.elapsed(at: ctx.date)))")
        }
        .padding(.vertical, 12)
    }

    private func pausedBar(_ commands: any MatchCommands) -> some View {
        VStack(spacing: 8) {
            Label("Paused", systemImage: "pause.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Button {
                attempt($error) { try commands.resumeMatch(matchID) }
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }

    private func end(_ action: EndAction, _ commands: any MatchCommands, anyway: Bool = false) {
        do {
            switch action {
            case .finish: try commands.finishMatch(matchID, anyway: anyway)
            case .abandon: try commands.abandonMatch(matchID)
            case .cancel: try commands.cancelMatch(matchID)
            }
            dismiss()
        } catch MatchCommandError.finishShortOfTarget {
            finishAnyway = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func targetTitle(_ screen: LiveMatchScreen) -> String {
        let name = screen.sides.first { $0.id == screen.targetReachedBy }?.name ?? ""
        return "\(name) wins?"
    }

    private func endTitle(_ screen: LiveMatchScreen) -> String {
        switch ending {
        case .finish: "Finish this match?"
        case .abandon: "Abandon this match?"
        case .cancel: "Cancel this match?"
        case nil: ""
        }
    }

    private func endButton(_ action: EndAction) -> String {
        switch action {
        case .finish: "Finish Match"
        case .abandon: "Abandon Match"
        case .cancel: "Cancel Match"
        }
    }

    private func endMessage(_ action: EndAction, _ screen: LiveMatchScreen) -> String {
        switch action {
        case .finish: "The result goes into the history at \(screen.sides.map { "\($0.frames)" }.joined(separator: "–"))."
        case .abandon: "It stays in the history, marked abandoned."
        case .cancel: "The match is discarded and not kept in the history."
        }
    }

    private func keepAwake(_ on: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}

/// One player's column: plate, name, breaker dot, huge score, big +, smaller −.
struct PlayerColumn: View {
    let side: LiveSide
    let screen: LiveMatchScreen
    @Binding var error: String?
    @Environment(\.matchesPorts) private var ports
    @ScaledMetric(relativeTo: .largeTitle) private var plusHeight: CGFloat = 96

    var body: some View {
        let colour = PlayerColour.color(side.colour)
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Capsule().fill(colour).frame(height: 8)
                HStack(spacing: 6) {
                    Text(side.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Circle()
                        .fill(side.isBreaker ? Color.primary : .clear)
                        .frame(width: 10, height: 10)
                }
            }
            ScoreNumeral(side.frames, size: .hero)
                .foregroundStyle(screen.isPaused ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: side.frames)
            Spacer(minLength: 0)
            if screen.controls.chooseBreaker {
                Button {
                    attempt($error) { try ports?.commands.chooseBreaker(screen.id, player: side.id) }
                } label: {
                    Text("\(side.name) breaks")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: plusHeight)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    attempt($error) { try ports?.commands.awardFrame(screen.id, to: side.id) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 44, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: plusHeight)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!screen.controls.award)
                .accessibilityLabel("Frame to \(side.name)")

                Button {
                    attempt($error) { try ports?.commands.removeFrame(screen.id, from: side.id) }
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!screen.controls.removeFrom.contains(side.id))
                .accessibilityLabel("Take a frame off \(side.name)")
            }
        }
        .padding(.bottom)
        .sensoryFeedback(trigger: side.frames) { old, new in new > old ? .increase : .decrease }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(side.name) \(side.frames)\(side.isBreaker ? ", to break" : "")")
    }
}
