import DesignSystem
import MatchesApplication
import SwiftUI

/// New Game › Enter details (spec 010): two players, game, style and targets, break rule.
/// Starting opens the live screen, which asks who breaks.
public struct NewGameView: View {
    let onStart: (MatchID) -> Void
    @Environment(\.matchesPorts) private var ports
    @State private var selected: [PlayerRef] = []
    @State private var game = Game.pool
    @State private var style = MatchStyle.mostFramesWins
    @State private var breakRule = BreakRule.alternate
    @State private var newName = ""
    @State private var error: String?
    @State private var loaded = false

    public init(onStart: @escaping (MatchID) -> Void) {
        self.onStart = onStart
    }

    public var body: some View {
        let players = ports?.players.suggestions ?? []
        Form {
            Section {
                ForEach(players) { player in
                    Button { toggle(player.id) } label: {
                        HStack {
                            PlayerPlate(name: player.name, colour: PlayerColour.color(player.colour))
                            Spacer()
                            if let i = selected.firstIndex(of: player.id) {
                                Image(systemName: "\(i + 1).circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel(i == 0 ? "First player" : "Second player")
                            }
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 36)
                    }
                    .tint(.primary)
                }
                HStack {
                    TextField("Add player", text: $newName)
                        .nameEntry()
                        .onSubmit(addPlayer)
                    Button("Add", action: addPlayer)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Players")
            } footer: {
                Text("Pick two.")
            }

            Section {
                Picker("Game", selection: $game) {
                    ForEach(Game.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Match") {
                MatchStyleEditor(style: $style)
                Picker("Break", selection: $breakRule) {
                    ForEach(BreakRule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                Button(action: start) {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.count != 2)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("New Game")
        .errorAlert($error)
        .onAppear(perform: loadDefaults)
    }

    private func loadDefaults() {
        guard !loaded, let ports else { return }
        loaded = true
        let d = ports.settings.defaults
        (game, style, breakRule) = (d.game, d.style, d.breakRule)
        if let me = ports.players.me { selected = [me] }
    }

    private func toggle(_ id: PlayerRef) {
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else {
            if selected.count == 2 { selected.removeLast() }
            selected.append(id)
        }
    }

    private func addPlayer() {
        guard let ports, !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        attempt($error) {
            let colour = PlayerColour.nextUnused(ports.players.suggestions.map(\.colour)).rawValue
            let player = try ports.players.addPlayer(named: newName, colour: colour)
            newName = ""
            if selected.count < 2 { selected.append(player.id) }
        }
    }

    private func start() {
        guard let ports else { return }
        attempt($error) {
            let id = try ports.commands.startMatch(MatchSetup(players: selected, game: game, style: style, breakRule: breakRule))
            onStart(id)
        }
    }
}

/// Style and targets as entered: most frames wins, race to N, or best of N (odd only).
public struct MatchStyleEditor: View {
    @Binding var style: MatchStyle

    public init(style: Binding<MatchStyle>) {
        _style = style
    }

    private enum Kind: String, CaseIterable { case most = "Most frames wins", race = "Race to", best = "Best of" }

    private var kind: Binding<Kind> {
        Binding {
            switch style {
            case .mostFramesWins: .most
            case .raceTo: .race
            case .bestOf: .best
            }
        } set: { kind in
            switch kind {
            case .most: style = .mostFramesWins
            case .race: style = .raceTo(target ?? 3)
            case .best: style = .bestOf(target.map { $0 * 2 - 1 } ?? 5)
            }
        }
    }

    /// Frames to win, used to carry the target across a kind change.
    private var target: Int? { style.framesToWin }

    public var body: some View {
        Picker("Style", selection: kind) {
            ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        switch style {
        case .mostFramesWins:
            EmptyView()
        case .raceTo(let n):
            Stepper(value: Binding { n } set: { style = .raceTo($0) }, in: 1...30) {
                LabeledContent("Race to", value: "\(n)").monospacedDigit()
            }
        case .bestOf(let n):
            Stepper(value: Binding { n } set: { style = .bestOf($0) }, in: 1...59, step: 2) {
                LabeledContent("Best of", value: "\(n)").monospacedDigit()
            }
        }
    }
}

/// Settings › Match defaults (spec 007). Changes apply to new matches only.
public struct MatchDefaultsSection: View {
    @Environment(\.matchesPorts) private var ports
    @State private var error: String?

    public init() {}

    public var body: some View {
        if let settings = ports?.settings {
            let defaults = Binding { settings.defaults } set: { new in attempt($error) { try settings.changeDefaults(new) } }
            Section {
                Picker("Game", selection: defaults.game) {
                    ForEach(Game.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                MatchStyleEditor(style: defaults.style)
                Picker("Break", selection: defaults.breakRule) {
                    ForEach(BreakRule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("New Matches")
            } footer: {
                Text("Changes apply to new matches only.")
            }
            Section {
                Stepper(value: Binding { settings.liveMatchLimit } set: { settings.changeLiveMatchLimit($0) }, in: 1...100) {
                    LabeledContent("Live match limit", value: "\(settings.liveMatchLimit)").monospacedDigit()
                }
            }
            .errorAlert($error)
        }
    }
}
