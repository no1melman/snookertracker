import DesignSystem
import MatchesApplication
import SwiftUI
import UpgradePublished

/// New Game: recent setups (`TemplateList`, spec 008) on top, most used first: one tap starts that
/// match, swipe deletes the template. Below, Enter details (spec 010): two players, game, style and
/// targets, break rule. With no templates the screen is just the details step.
/// Starting either way opens the live screen, which asks who breaks.
public struct NewGameView: View {
    let onStart: (MatchID) -> Void
    @Environment(\.matchesPorts) private var ports
    @Environment(\.archivePlayer) private var archivePlayer
    @State private var selected: [PlayerRef] = []
    @State private var game = Game.pool
    @State private var style = MatchStyle.mostFramesWins
    @State private var breakRule = BreakRule.alternate
    @State private var newName = ""
    @State private var error: String?
    @State private var loaded = false
    /// Waiting on "already in a live match?" (S11).
    @State private var alreadyLive: AlreadyLive?
    /// The live-match limit that refused the start (S44).
    @State private var limitReached: Int?
    @State private var showsLimitSetting = false

    public init(onStart: @escaping (MatchID) -> Void) {
        self.onStart = onStart
    }

    public var body: some View {
        let players = ports?.players.suggestions ?? []
        let templates = ports?.templates?.templates ?? []
        Form {
            if !templates.isEmpty {
                Section("Recent") {
                    ForEach(templates) { template in
                        TemplateRowButton(template: template) { start(template.setup) }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(template) }
                                    .labelStyle(.iconOnly)
                            }
                    }
                }
            }

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
                    .swipeActions {
                        if let archivePlayer {
                            // No confirmation: Unarchive reverses it (ADR-0008, S34).
                            Button("Archive", systemImage: "archivebox") { archive(player.id, with: archivePlayer) }
                                .labelStyle(.iconOnly)
                                .tint(.orange)
                        }
                    }
                }
                HStack {
                    TextField("Add player", text: $newName)
                        .nameEntry()
                        .onSubmit(addPlayer)
                    Button("Add", action: addPlayer)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text(templates.isEmpty ? "Players" : "Or enter details")
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
        .confirmationDialog(
            alreadyLive.map(Self.alreadyLiveTitle) ?? "",
            isPresented: Binding(get: { alreadyLive != nil }, set: { if !$0 { alreadyLive = nil } }),
            titleVisibility: .visible, presenting: alreadyLive
        ) { pending in
            Button("Start Anyway") { confirmedStart(pending.setup) }
            Button("Don't Start", role: .cancel) {}
        } message: { _ in
            Text("Both matches stay live, with their own timers.")
        }
        .alert("Live match limit reached", isPresented: Binding(get: { limitReached != nil }, set: { if !$0 { limitReached = nil } })) {
            Button("Change Limit") { showsLimitSetting = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("You already have \(limitReached ?? 0) live matches. Finish one, or raise the limit in Settings.")
        }
        .sheet(isPresented: $showsLimitSetting) {
            NavigationStack {
                Form { MatchDefaultsSection() }
                    .navigationTitle("Settings")
                    .inlineTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showsLimitSetting = false } }
                    }
            }
        }
    }

    struct AlreadyLive {
        let setup: MatchSetup
        let players: [MatchPlayer]
    }

    static func alreadyLiveTitle(_ pending: AlreadyLive) -> String {
        let names = pending.players.map(\.name)
        let who = names.count > 1 ? names.joined(separator: " and ") + " are" : (names.first ?? "") + " is"
        return "\(who) already in a live match. Start another?"
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
        do {
            let colour = PlayerColour.nextUnused(ports.players.suggestions.map(\.colour)).rawValue
            let player = try ports.players.addPlayer(named: newName, colour: colour)
            newName = ""
            if selected.count < 2 { selected.append(player.id) }
        } catch let refused as UpgradeRequired {
            ports.showUpgradeOffer(refused.feature)  // S3: the Free player cap (S52)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func start() {
        start(MatchSetup(players: selected, game: game, style: style, breakRule: breakRule))
    }

    /// S11: a player already in a live match can play another after "are you sure?".
    private func start(_ setup: MatchSetup) {
        guard let ports else { return }
        attempt($error) {
            let live = try ports.commands.playersAlreadyLive(setup)
            if live.isEmpty { confirmedStart(setup) } else { alreadyLive = AlreadyLive(setup: setup, players: live) }
        }
    }

    /// The live-match limit refusal (S44) explains itself and offers the limit setting.
    private func confirmedStart(_ setup: MatchSetup) {
        guard let ports else { return }
        do {
            onStart(try ports.commands.startMatch(setup))
        } catch MatchCommandError.liveMatchLimitReached(let limit) {
            limitReached = limit
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ template: TemplateRow) {
        guard let commands = ports?.templateCommands else { return }
        attempt($error) { try commands.deleteTemplate(template.id) }
    }

    /// The player drops out of the list (suggestions are active players); a refusal (in a live
    /// match) explains itself.
    private func archive(_ player: PlayerRef, with archivePlayer: ArchivePlayerAction) {
        attempt($error) {
            try archivePlayer(player)
            selected.removeAll { $0 == player }
        }
    }
}

/// `ArchivePlayer` (S34, ADR-0008), supplied by the composition root because Matches can't import
/// Players. Throws the refusal (e.g. the player is in a live match) as a `LocalizedError`.
public typealias ArchivePlayerAction = @MainActor @Sendable (PlayerRef) throws -> Void

public extension EnvironmentValues {
    /// nil hides the swipe-to-archive action on New Game's player list.
    @Entry var archivePlayer: ArchivePlayerAction? = nil
}

/// One recent setup: both players' plates, then the game, the style and targets as entered and the
/// break rule. Tapping it starts that match.
struct TemplateRowButton: View {
    let template: TemplateRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ForEach(Array(template.players.enumerated()), id: \.offset) { i, player in
                            if i > 0 { Text("v").font(.subheadline).foregroundStyle(.secondary) }
                            PlayerPlate(name: player.name, colour: PlayerColour.color(player.colour))
                                .font(.body.weight(.semibold))
                        }
                    }
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
            .padding(.vertical, 2)
        }
        .tint(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.players.map(\.name).joined(separator: " v ")), \(details)")
        .accessibilityHint("Starts this match")
        .accessibilityAddTraits(.isButton)
    }

    /// "Pool · Race to 5 · Alternate breaks"
    private var details: String {
        let rule = template.breakRule == .alternate ? "Alternate breaks" : "Winner breaks"
        return [template.game.title, template.style.title, rule].joined(separator: " · ")
    }
}

/// Style and targets as entered: most frames wins, race to N, or best of N (odd only).
public struct MatchStyleEditor: View {
    @Binding var style: MatchStyle

    public init(style: Binding<MatchStyle>) {
        _style = style
    }

    private enum Kind: String, CaseIterable {
        case most = "Most frames wins", race = "Race to", best = "Best of", sets = "Sets"
    }

    private var kind: Binding<Kind> {
        Binding {
            switch style {
            case .mostFramesWins: .most
            case .raceTo: .race
            case .bestOf: .best
            case .sets: .sets
            }
        } set: { kind in
            switch kind {
            case .most: style = .mostFramesWins
            case .race: style = .raceTo(target ?? 3)
            case .best: style = .bestOf(target.map { $0 * 2 - 1 } ?? 5)
            case .sets: style = .sets(sets: 2, frames: target ?? 3)
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
        case .sets(let sets, let frames):
            Stepper(value: Binding { sets } set: { style = .sets(sets: $0, frames: frames) }, in: 1...15) {
                LabeledContent("Race to sets", value: "\(sets)").monospacedDigit()
            }
            Stepper(value: Binding { frames } set: { style = .sets(sets: sets, frames: $0) }, in: 1...30) {
                LabeledContent("Frames per set", value: "Race to \(frames)").monospacedDigit()
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
