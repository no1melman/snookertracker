import DesignSystem
import MatchesApplication
import SwiftUI
import UpgradePublished
#if canImport(UIKit)
import UIKit
#endif

/// The live screen (specs 009, 010): two player columns, huge scores, + / −, timers, pause, end.
public struct LiveMatchView: View {
    let matchID: MatchID
    @Environment(\.matchesPorts) private var ports
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var error: String?
    @State private var ending: EndAction?
    /// Set when Finish was refused short of the target: ask before finishing anyway.
    @State private var finishAnyway = false
    /// The set win the scorer chose to continue from (S16), so its prompt doesn't come back.
    @State private var continuedSet: SetWonPrompt?
    /// The scorer kept both players in the same colour (S46).
    @State private var keepSameColour = false

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
        .onAppear { keepAwake(true); allowLandscape(true) }
        .onDisappear { keepAwake(false); allowLandscape(false) }
    }

    /// An iPhone on its side has a compact height: the side-by-side layout (spec 030).
    private var landscape: Bool { verticalSizeClass == .compact }

    @ViewBuilder
    private func content(_ screen: LiveMatchScreen, _ commands: any MatchCommands) -> some View {
        VStack(spacing: 0) {
            // Landscape (spec 030): the clocks move into the navigation bar, so the scores get the height.
            if !landscape { header(screen) }
            Scoreboard(screen: screen, landscape: landscape, error: $error)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
            if screen.headToHeadLocked, screen.sides.count == 2 {
                // Free (S14, S52): greyed, with an upgrade prompt instead of the figures.
                LockedHeadToHeadStrip(compact: landscape) { ports?.showUpgradeOffer(.headToHead) }
            } else if let lookup = ports?.headToHead, screen.sides.count == 2 {
                let record = lookup(screen.sides[0].id, screen.sides[1].id)
                if !record.isEmpty { HeadToHeadStrip(record: record, sides: screen.sides, compact: landscape) }
            }
            // Landscape: "Paused" shows in the navigation bar and Resume stays in the toolbar.
            if screen.isPaused, !landscape { pausedBar(screen, commands) }
        }
        .navigationTitle(screen.style.title)
        .inlineTitle()
        .toolbar {
            if landscape {
                ToolbarItem(placement: .principal) { header(screen) }
            }
            ToolbarItem(placement: .primaryAction) {
                if screen.isPaused {
                    if screen.controls.resumeOffersUpgrade {
                        Button("Upgrade now", systemImage: "lock.fill") { ports?.showUpgradeOffer(.manualPause) }
                    } else {
                        Button("Resume", systemImage: "play.fill") { attemptOrOffer($error, ports) { try commands.resumeMatch(matchID) } }
                    }
                } else if screen.controls.pauseOffersUpgrade {
                    // Free (S7, S52): the pause button shows "Upgrade now" in place.
                    Button("Upgrade now", systemImage: "lock.fill") { ports?.showUpgradeOffer(.manualPause) }
                        .disabled(!screen.controls.pause)
                } else {
                    Button("Pause", systemImage: "pause.fill") { attemptOrOffer($error, ports) { try commands.pauseMatch(matchID) } }
                        .disabled(!screen.controls.pause)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Menu("Correct Breaker", systemImage: "arrow.left.arrow.right") {
                        ForEach(screen.sides) { side in
                            Button("\(side.name) is breaking") {
                                attempt($error) { try commands.correctBreaker(matchID, player: side.id) }
                            }
                            .disabled(side.isBreaker)
                        }
                    }
                    .disabled(!screen.controls.correctBreaker)
                    Divider()
                    Button("Finish Match", systemImage: "flag.checkered") { ending = .finish }
                    Button("Abandon Match", systemImage: "xmark.circle") { ending = .abandon }
                    Button("Cancel Match", systemImage: "trash", role: .destructive) { ending = .cancel }
                }
            }
        }
        .confirmationDialog(endTitle(screen), isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }), titleVisibility: .visible, presenting: ending) { action in
            Button(Self.endButton(action), role: action == .cancel ? .destructive : nil) { end(action, commands) }
        } message: { action in
            Text(Self.endMessage(action, frames: screen.sides.map(\.frames)))
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
            Text("\(scoreLine(screen)). Undo if the frame was a mis-tap.")
        }
        // S16: a set won short of the match. + stays behind the prompt until Continue or Undo (Q3).
        .alert(setTitle(screen), isPresented: .constant(showsContinue(screen))) {
            Button("Continue") { continuedSet = screen.setWon }
            Button("Undo Last Frame", role: .cancel) {
                if let p = screen.setWon?.winner { attempt($error) { try commands.removeFrame(matchID, from: p) } }
            }
        } message: {
            Text("\(scoreLine(screen)). Undo if the frame was a mis-tap.")
        }
        // S46: both players share a colour; offer one of them a temporary colour for this match.
        .alert("Same colour", isPresented: .constant(screen.coloursClash && !keepSameColour && ending == nil)) {
            Button("Use a Temporary Colour") { overrideColour(screen, commands) }
            Button("Keep Both", role: .cancel) { keepSameColour = true }
        } message: {
            Text("\(screen.sides.map(\.name).joined(separator: " and ")) are both \(screen.sides.first?.colour ?? ""). Give \(recolouredSide(screen)?.name ?? "one of them") a different colour for this match only?")
        }
    }

    private func showsContinue(_ screen: LiveMatchScreen) -> Bool {
        guard let won = screen.setWon else { return false }
        return won != continuedSet && screen.targetReachedBy == nil && ending == nil && !screen.isPaused
    }

    private func setTitle(_ screen: LiveMatchScreen) -> String {
        guard let won = screen.setWon else { return "" }
        let name = screen.sides.first { $0.id == won.winner }?.name ?? ""
        return "\(name) wins set \(won.setNumber). Continue?"
    }

    /// "Callum 3 – 1 Asher", or for sets "Callum (1) 0 – 0 (0) Asher".
    private func scoreLine(_ screen: LiveMatchScreen) -> String {
        guard screen.sides.count == 2 else { return "" }
        return "\(screen.sides[0].name) \(screen.scoreText) \(screen.sides[1].name)"
    }

    /// The side given the temporary colour: the opponent of Me when Me plays, else the second side.
    private func recolouredSide(_ screen: LiveMatchScreen) -> LiveSide? {
        if let me = ports?.players.me, screen.sides.contains(where: { $0.id == me }) {
            return screen.sides.first { $0.id != me }
        }
        return screen.sides.last
    }

    private func overrideColour(_ screen: LiveMatchScreen, _ commands: any MatchCommands) {
        guard let side = recolouredSide(screen) else { return }
        let shared = side.colour
        let colour = PlayerColour.allCases.filter { $0.rawValue != shared }.randomElement() ?? .gray
        do {
            try commands.overrideMatchColour(matchID, of: side.id, to: colour.rawValue)
        } catch {
            keepSameColour = true
            self.error = error.localizedDescription
        }
    }

    private func header(_ screen: LiveMatchScreen) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            // Landscape (spec 030): one line, so the scores get the height.
            let layout = landscape ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12)) : AnyLayout(VStackLayout(spacing: 4))
            layout {
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
                    if landscape {
                        Text(screen.style.title)
                    } else {
                        Text(screen.startedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    }
                    if landscape, screen.isPaused {
                        Text("Paused").fontWeight(.semibold).foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            // Read first: "Asher 4, Me 3. Asher to break. Paused. Frame 8, …".
            .accessibilityLabel([
                spokenScore(screen.sides),
                screen.sides.first(where: \.isBreaker).map { "\($0.name) to break" },
                screen.isPaused ? "Paused" : nil,
                "Frame \(screen.frameNumber), \(spokenDuration(screen.frameTimer.elapsed(at: ctx.date)))",
                "Match time \(spokenDuration(screen.matchTimer.elapsed(at: ctx.date)))",
            ].compactMap { $0 }.joined(separator: ". "))
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.vertical, landscape ? 0 : 12)
    }

    private func pausedBar(_ screen: LiveMatchScreen, _ commands: any MatchCommands) -> some View {
        let layout = landscape ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            Label("Paused", systemImage: "pause.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Button {
                // Free: a pause by hand can't be resumed (S8, S52); an automatic one can.
                if screen.controls.resumeOffersUpgrade {
                    ports?.showUpgradeOffer(.manualPause)
                } else {
                    attemptOrOffer($error, ports) { try commands.resumeMatch(matchID) }
                }
            } label: {
                Label(screen.controls.resumeOffersUpgrade ? "Upgrade now" : "Resume",
                      systemImage: screen.controls.resumeOffersUpgrade ? "lock.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(landscape ? 8 : 16)
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
        ending.map(Self.endTitle) ?? ""
    }

    static func endTitle(_ action: EndAction) -> String {
        switch action {
        case .finish: "Finish this match?"
        case .abandon: "Abandon this match?"
        case .cancel: "Cancel this match?"
        }
    }

    static func endButton(_ action: EndAction) -> String {
        switch action {
        case .finish: "Finish Match"
        case .abandon: "Abandon Match"
        case .cancel: "Cancel Match"
        }
    }

    static func endMessage(_ action: EndAction, frames: [Int]) -> String {
        switch action {
        case .finish: "The result goes into the history at \(frames.map(String.init).joined(separator: "–"))."
        case .abandon: "It stays in the history, marked abandoned."
        case .cancel: "The match is discarded and not kept in the history."
        }
    }

    private func keepAwake(_ on: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }

    /// Only this screen turns sideways; leaving it puts the app back in portrait (spec 030).
    private func allowLandscape(_ on: Bool) {
        #if canImport(UIKit)
        OrientationLock.allowLandscape(on)
        #endif
    }
}

/// The players and their scores (spec 030). The breaker's column and score are a little bigger, the
/// + and − are the same size on both sides, and a score keeps its size whatever its number of digits.
/// Portrait: a column per player with the buttons underneath. Landscape: side by side, with each
/// player's buttons on the outer edge next to their score.
struct Scoreboard: View {
    let screen: LiveMatchScreen
    let landscape: Bool
    @Binding var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 190
    @ScaledMetric(relativeTo: .largeTitle) private var plusHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .title) private var setsHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .title2) private var landscapeButtons: CGFloat = 120

    private let spacing: CGFloat = 12
    private var breaker: Int? { screen.sides.firstIndex(where: \.isBreaker) }
    private var sides: [(offset: Int, element: LiveSide)] { Array(screen.sides.enumerated()) }

    var body: some View {
        GeometryReader { geo in
            // A match is two players; anything else keeps the columns.
            if landscape, screen.sides.count == 2 { sideBySide(geo.size.width) } else { columns(geo.size.width) }
        }
        .animation(reduceMotion ? nil : .snappy, value: breaker)
    }

    /// Rows of names, scores and buttons sharing the column widths; the scores take the height left over.
    private func columns(_ width: CGFloat) -> some View {
        let scoreWidth = width - gaps
        let widths = columnWidths(scoreWidth)
        let buttonWidth = widths.min() ?? 0
        return VStack(spacing: spacing) {
            headings(widths, compact: false)
            scores(scoreWidth, widths, cap: heroSize)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(sides, id: \.element.id) { i, side in
                    FrameButtons(side: side, screen: screen, error: $error, plusHeight: plusHeight, fills: false)
                        .frame(width: buttonWidth)
                        .frame(width: widths[i])
                }
            }
        }
        .padding(.bottom)
    }

    /// Each player's buttons on the outer edge, the names and scores between them.
    private func sideBySide(_ width: CGFloat) -> some View {
        let scoreWidth = width - 2 * landscapeButtons - 2 * spacing - gaps
        let widths = columnWidths(scoreWidth)
        return HStack(spacing: spacing) {
            buttons(screen.sides[0])
            VStack(spacing: spacing) {
                headings(widths, compact: true)
                // Landscape scores are meant to be much bigger: the hero size isn't the limit here, the height is.
                scores(scoreWidth, widths, cap: heroSize * 2)
            }
            buttons(screen.sides[1])
        }
    }

    private var gaps: CGFloat { spacing * CGFloat(max(screen.sides.count - 1, 0)) }

    private func columnWidths(_ scoreWidth: CGFloat) -> [CGFloat] {
        ScoreboardSizing(width: scoreWidth, height: 0, breaker: breaker, sides: screen.sides.count, cap: heroSize).widths
    }

    private func headings(_ widths: [CGFloat], compact: Bool) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(sides, id: \.element.id) { i, side in
                PlayerHeading(side: side, emphasised: emphasised(i), compact: compact)
                    .frame(width: widths[i])
            }
        }
    }

    /// Sized from the height actually left, so nothing above or below is squeezed to make room.
    private func scores(_ scoreWidth: CGFloat, _ widths: [CGFloat], cap: CGFloat) -> some View {
        GeometryReader { geo in
            let sets = screen.sides.contains { $0.sets != nil } ? setsHeight : 0
            let sizing = ScoreboardSizing(width: scoreWidth, height: geo.size.height - sets,
                                          breaker: breaker, sides: screen.sides.count, cap: cap)
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                ForEach(sides, id: \.element.id) { i, side in
                    PlayerScore(side: side, screen: screen, points: sizing.fontSizes[i])
                        .frame(width: widths[i])
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func buttons(_ side: LiveSide) -> some View {
        FrameButtons(side: side, screen: screen, error: $error, plusHeight: plusHeight, fills: true)
            .frame(width: landscapeButtons)
            .padding(.vertical, spacing)
    }

    /// Two sides only: nil before a breaker is chosen, so both read the same.
    private func emphasised(_ i: Int) -> Bool? {
        guard let breaker, screen.sides.count == 2 else { return nil }
        return i == breaker
    }
}

/// Plate, name and breaker dot. The breaker's name is a size up from the other player's.
struct PlayerHeading: View {
    let side: LiveSide
    /// true for the breaker, false for the other player, nil when neither is emphasised.
    let emphasised: Bool?
    /// Landscape: a thinner plate, to leave the height to the score.
    var compact = false

    var body: some View {
        // Free: no colours shown (ADR-0010).
        let colour = side.showsColour ? PlayerColour.color(side.colour) : Color.secondary.opacity(0.3)
        VStack(spacing: compact ? 4 : 8) {
            Capsule().fill(colour).frame(height: compact ? 6 : 8)
            HStack(spacing: 6) {
                Text(side.name)
                    .font(emphasised == false ? .title3.weight(.semibold) : .title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Circle()
                    .fill(side.isBreaker ? Color.primary : .clear)
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The score at an exact size, never shrunk to fit; sets (S16) show sets won in brackets underneath.
struct PlayerScore: View {
    let side: LiveSide
    let screen: LiveMatchScreen
    let points: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            ScoreNumeral(side.scoreFrames, size: .points(points))
                .foregroundStyle(screen.isPaused ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: side.scoreFrames)
            if let sets = side.sets {
                Text("(\(sets.setsWon))")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .sensoryFeedback(trigger: side.frames) { old, new in new > old ? .increase : .decrease }
    }
}

/// "X breaks" before a breaker is chosen, then a big + and a smaller −. The same size for both players.
struct FrameButtons: View {
    let side: LiveSide
    let screen: LiveMatchScreen
    @Binding var error: String?
    let plusHeight: CGFloat
    /// Landscape: the + grows to fill the height beside the score.
    let fills: Bool
    @Environment(\.matchesPorts) private var ports

    var body: some View {
        VStack(spacing: 12) {
            if screen.controls.chooseBreaker {
                Button {
                    attempt($error) { try ports?.commands.chooseBreaker(screen.id, player: side.id) }
                } label: {
                    Text("\(side.name) breaks")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: fills ? 44 : plusHeight, maxHeight: fills ? .infinity : nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    attempt($error) { try ports?.commands.awardFrame(screen.id, to: side.id) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 44, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: fills ? 44 : plusHeight, maxHeight: fills ? .infinity : nil)
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
    }
}

/// Free (S14, S52): the head-to-head strip, greyed, with an upgrade prompt instead of the figures.
/// Compact (landscape, spec 030): one line.
struct LockedHeadToHeadStrip: View {
    var compact = false
    let upgrade: () -> Void

    var body: some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            Text("Head to head")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Button(action: upgrade) {
                Label("Upgrade now to see who's ahead", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, compact ? 0 : 10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5))
        .foregroundStyle(.secondary)
    }
}

/// The all-time head-to-head (S14) under the columns, from each column's point of view: matches,
/// frames, and deciders only when there are any. Hidden when the players have no finished match.
/// Compact (landscape, spec 030): one line, "Matches 5 – 3 · Frames 20 – 14".
struct HeadToHeadStrip: View {
    let record: LiveHeadToHead
    let sides: [LiveSide]
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 16) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    pair("Matches", record.won, record.lost)
                    pair("Frames", record.framesWon, record.framesLost)
                    if record.showsDeciders { pair("Deciders", record.decidersWon, record.decidersLost) }
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    row("Matches", record.won, record.lost)
                    row("Frames", record.framesWon, record.framesLost)
                    if record.showsDeciders { row("Deciders", record.decidersWon, record.decidersLost) }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var title: String {
        record.drawn > 0 ? "Head to head · \(record.drawn) drawn" : "Head to head"
    }

    private func row(_ title: String, _ first: Int, _ second: Int) -> some View {
        HStack {
            Text(first, format: .number).frame(maxWidth: .infinity)
            Text(title).font(.subheadline).foregroundStyle(.secondary).frame(minWidth: 80)
            Text(second, format: .number).frame(maxWidth: .infinity)
        }
        .font(.headline)
        .monospacedDigit()
    }

    private func pair(_ title: String, _ first: Int, _ second: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text("\(first) – \(second)").font(.headline).monospacedDigit()
        }
    }

    /// "Head to head: Asher won 5, Me won 3, 1 drawn. Frames 20 to 14. Deciders 3 to 1."
    private var spoken: String {
        let (a, b) = (sides.first?.name ?? "", sides.last?.name ?? "")
        var parts = ["Head to head: \(a) won \(record.won), \(b) won \(record.lost)"]
        if record.drawn > 0 { parts[0] += ", \(record.drawn) drawn" }
        parts.append("Frames \(record.framesWon) to \(record.framesLost)")
        if record.showsDeciders { parts.append("Deciders \(record.decidersWon) to \(record.decidersLost)") }
        return parts.joined(separator: ". ")
    }
}
