import ActivityKit
import AppIntents
import DesignSystem
import LiveActivityShared
import SwiftUI
import WidgetKit

// The lock-screen match (spec 018, design language 022): player colour bars and names, the score
// in monospaced digits, the breaker dot, the frame timer, + per player and Pause or Resume.

@main
struct LiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        MatchLiveActivity()
    }
}

typealias MatchState = MatchActivityAttributes.ContentState

struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            LockScreenMatchView(state: context.state)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedSide(side: state.sides[0], paused: state.isPaused, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedSide(side: state.sides[1], paused: state.isPaused, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    FrameClock(state: state, font: .headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MatchButtons(state: state, compact: true)
                }
            } compactLeading: {
                CompactScore(side: state.sides[0], paused: state.isPaused, plateFirst: true)
            } compactTrailing: {
                CompactScore(side: state.sides[1], paused: state.isPaused, plateFirst: false)
            } minimal: {
                Text("\(state.sides[0].frames)–\(state.sides[1].frames)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(state.isPaused ? .secondary : .primary)
                    .accessibilityLabel(state.spokenScore)
            }
            .keylineTint(PlayerColour.color(state.sides[0].colour))
        }
    }
}

// MARK: - Lock screen

/// One compact row (colour bar, name, score | frame clock | score, name, colour bar) over one row of
/// controls, so the activity stays well inside the lock screen's height limit.
struct LockScreenMatchView: View {
    let state: MatchState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                SideRow(side: state.sides[0], paused: state.isPaused, leading: true)
                FrameClock(state: state, font: .subheadline)
                    .fixedSize()
                SideRow(side: state.sides[1], paused: state.isPaused, leading: false)
            }
            MatchButtons(state: state, compact: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Colour bar, name with the breaker dot, then the score; mirrored for the right-hand side. The name
/// gives way to the score when space is short.
struct SideRow: View {
    let side: MatchState.Side
    let paused: Bool
    let leading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if leading {
                bar
                name
                Spacer(minLength: 4)
                score
            } else {
                score
                Spacer(minLength: 4)
                name
                bar
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.name) \(side.frames)\(side.isBreaker ? ", to break" : "")")
    }

    private var bar: some View {
        Capsule().fill(PlayerColour.color(side.colour)).frame(width: 4, height: 30)
    }

    private var name: some View {
        HStack(spacing: 4) {
            if !leading { BreakerDot(isBreaker: side.isBreaker) }
            Text(side.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
            if leading { BreakerDot(isBreaker: side.isBreaker) }
        }
    }

    private var score: some View {
        Text(side.frames, format: .number)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(side.frames)))
            .opacity(paused ? 0.5 : 1)
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)
    }
}

struct BreakerDot: View {
    let isBreaker: Bool

    var body: some View {
        Circle()
            .fill(isBreaker ? Color.primary : .clear)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// "Frame 4" over the running frame timer; frozen, with a Paused label, while paused.
struct FrameClock: View {
    let state: MatchState
    let font: Font

    var body: some View {
        let frame = state.sides.reduce(0) { $0 + $1.frames } + 1
        VStack(spacing: 1) {
            if state.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("Frame \(frame)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(timerInterval: state.frameTimerStart...Date.distantFuture, pauseTime: state.pausedAt,
                 countsDown: false, showsHours: true)
                .font(font.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .opacity(state.isPaused ? 0.5 : 1)
                .frame(width: 60)
        }
        .accessibilityElement(children: .combine)
    }
}

/// + for each player, with Pause between; a single Resume while paused. With no + to offer, one
/// short line of status (and Pause, if allowed) instead.
struct MatchButtons: View {
    let state: MatchState
    let compact: Bool

    var body: some View {
        let height: CGFloat = compact ? 36 : 40
        HStack(spacing: 8) {
            if state.canResume {
                Button(intent: ResumeMatchIntent(match: state.matchID)) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .tint(.orange)
            } else if state.canAward {
                plus(state.sides[0], height: height)
                pause(height: height)
                plus(state.sides[1], height: height)
            } else {
                Text(state.canPause ? "Choose the breaker in the app" : "Target reached · finish in the app")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: state.canPause ? .leading : .center)
                if state.canPause { pause(height: 32) }
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
    }

    private func plus(_ side: MatchState.Side, height: CGFloat) -> some View {
        Button(intent: AwardFrameIntent(match: state.matchID, player: side.player)) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.body.weight(.bold))
                if !compact {
                    Text(side.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .tint(PlayerColour.color(side.colour))
        .accessibilityLabel("Frame to \(side.name)")
    }

    private func pause(height: CGFloat) -> some View {
        Button(intent: PauseMatchIntent(match: state.matchID)) {
            Image(systemName: "pause.fill")
                .font(.body.weight(.semibold))
                .frame(minWidth: height + 8, minHeight: height)
        }
        .tint(.gray)
        .accessibilityLabel("Pause")
    }
}

// MARK: - Dynamic Island

struct ExpandedSide: View {
    let side: MatchState.Side
    let paused: Bool
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 5) {
                if alignment == .trailing { BreakerDot(isBreaker: side.isBreaker) }
                Capsule().fill(PlayerColour.color(side.colour)).frame(width: 4, height: 14)
                Text(side.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                if alignment == .leading { BreakerDot(isBreaker: side.isBreaker) }
            }
            Text(side.frames, format: .number)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .opacity(paused ? 0.5 : 1)
                .contentTransition(.numericText(value: Double(side.frames)))
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.name) \(side.frames)")
    }
}

struct CompactScore: View {
    let side: MatchState.Side
    let paused: Bool
    let plateFirst: Bool

    var body: some View {
        HStack(spacing: 4) {
            if plateFirst { plate }
            Text(side.frames, format: .number)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .opacity(paused ? 0.5 : 1)
            if !plateFirst { plate }
        }
        .accessibilityLabel("\(side.name) \(side.frames)")
    }

    private var plate: some View {
        Capsule().fill(PlayerColour.color(side.colour)).frame(width: 4, height: 14)
    }
}

// MARK: - Previews

#if DEBUG
private let previewState = MatchState(
    matchID: UUID(),
    sides: [
        .init(player: UUID(), name: "Asher", colour: "orange", frames: 4, isBreaker: true),
        .init(player: UUID(), name: "Callum", colour: "blue", frames: 3, isBreaker: false),
    ],
    frameTimerStart: Date().addingTimeInterval(-247), pausedAt: nil, canAward: true, canPause: true, canResume: false)

#Preview("Lock screen", as: .content, using: MatchActivityAttributes()) {
    MatchLiveActivity()
} contentStates: {
    previewState
    MatchState(matchID: previewState.matchID, sides: previewState.sides, frameTimerStart: Date().addingTimeInterval(-600),
               pausedAt: Date(), canAward: false, canPause: false, canResume: true)
}
#endif
