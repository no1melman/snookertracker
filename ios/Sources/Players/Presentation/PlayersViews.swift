import DesignSystem
import PlayersApplication
import UpgradePublished
import SwiftUI

/// The Players application ports a view may use, injected by the composition root.
public struct PlayersPorts: Sendable {
    public let list: any PlayersListQuery
    public let commands: any PlayerCommands
    /// Upgrade's `CurrentEdition` (ADR-0011); Unlocked when not handed over.
    public let edition: any CurrentEdition
    /// Routes a refused paid feature to Upgrade's `ShowUpgradeOffer` (S52); a no-op when not handed over.
    public let showUpgradeOffer: ShowUpgradeOfferAction

    public init(
        list: any PlayersListQuery, commands: any PlayerCommands,
        edition: any CurrentEdition = FixedEdition.unlocked, showUpgradeOffer: @escaping ShowUpgradeOfferAction = { _ in }
    ) {
        self.edition = edition
        self.showUpgradeOffer = showUpgradeOffer
        self.list = list
        self.commands = commands
    }
}

public extension EnvironmentValues {
    @Entry var playersPorts: PlayersPorts? = nil
}

extension PlayersPorts {
    /// Colours are paid (S22): no colour plates or Colour action while Free.
    @MainActor var showsColours: Bool { edition.allows(.colours) }

    /// Whether one more active player fits the Free cap (read from `FreeLimits`); always once Unlocked.
    @MainActor var roomForAnotherActivePlayer: Bool {
        guard let limits = edition.limits else { return true }
        return limits.allowsAnotherActivePlayer(activeCount: list.players.filter { !$0.isArchived }.count)
    }
}

/// Runs `command`; an edition refusal opens the upgrade offer (S52), any other lands in `message`.
@MainActor func attempt(_ message: Binding<String?>, offer: ShowUpgradeOfferAction?, _ command: () throws -> Void) {
    do { try command() } catch let refused as UpgradeRequired {
        offer?(refused.feature)
    } catch {
        message.wrappedValue = error.localizedDescription
    }
}

/// A player's name with their colour plate, or the plain name while colours are omitted (Free).
struct PlayerLabel: View {
    let player: PlayerListItem

    var body: some View {
        if let colour = player.shownColour {
            PlayerPlate(name: player.name, colour: PlayerColour.color(colour), archived: player.isArchived)
        } else {
            Text(player.name)
                .lineLimit(1)
                .foregroundStyle(player.isArchived ? .secondary : .primary)
        }
    }
}

/// The Players screen (spec 011, ADR-0008): Active and Archived sections, add, and per row:
/// - swipe an active player → Archive (no confirmation: Unarchive reverses it);
/// - swipe an archived player → Remove (a confirmation stating the matches deleted, only when there are any);
/// - context menu: Rename, Colour, Merge into…, Archive / Unarchive, Remove.
/// Refusals (live match, played each other) come back as `errorAlert`s that explain themselves.
public struct PlayersView: View {
    @Environment(\.playersPorts) private var ports
    @State private var editing: PlayerEditor.Mode?
    @State private var merging: PlayerListItem?
    @State private var removal: Removal?
    @State private var error: String?

    public init() {}

    public var body: some View {
        let players = ports?.list.players ?? []
        let active = players.filter { !$0.isArchived }
        let archived = players.filter(\.isArchived)
        List {
            Section("Active") {
                ForEach(active) { row($0) }
            }
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { row($0) }
                }
            }
        }
        .overlay {
            if players.isEmpty {
                ContentUnavailableView("No Players", systemImage: "person.2", description: Text("Add the people you play."))
            }
        }
        .navigationTitle("Players")
        .toolbar {
            Button("Add Player", systemImage: "plus") {
                // S3: at the Free cap, adding opens the upgrade offer instead of the editor.
                if let ports, !ports.roomForAnotherActivePlayer {
                    ports.showUpgradeOffer(.extraPlayers)
                } else {
                    editing = .add
                }
            }
        }
        .sheet(item: $editing) { mode in
            NavigationStack { PlayerEditor(mode: mode) }
        }
        .sheet(item: $merging) { player in
            NavigationStack { MergePicker(foldedIn: player) }
        }
        .removalConfirmation($removal, error: $error)
        .errorAlert($error)
    }

    private func row(_ player: PlayerListItem) -> some View {
        Button { editing = .edit(player) } label: {
            HStack {
                PlayerLabel(player: player)
                if player.id == ports?.list.me?.id {
                    Text("Me").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .frame(minHeight: 36)
        }
        .tint(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: !player.isArchived) {
            if player.isArchived {
                Button("Remove", systemImage: "trash") { requestRemoval(of: player) }
                    .labelStyle(.iconOnly)
                    .tint(.red)
            } else {
                Button("Archive", systemImage: "archivebox") { archive(player) }
                    .labelStyle(.iconOnly)
                    .tint(.orange)
            }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { editing = .edit(player) }
            if ports?.showsColours == true {
                Button("Colour", systemImage: "paintpalette") { editing = .edit(player) }
            }
            if player.isArchived {
                Button("Unarchive", systemImage: "arrow.uturn.backward") {
                    // S35: at the Free cap this opens the upgrade offer.
                    attempt($error, offer: ports?.showUpgradeOffer) { try ports?.commands.unarchivePlayer(player.id) }
                }
                Button("Remove", systemImage: "trash", role: .destructive) { requestRemoval(of: player) }
            } else {
                Button("Merge into…", systemImage: "arrow.triangle.merge") { merging = player }
                Button("Archive", systemImage: "archivebox") { archive(player) }
            }
        }
    }

    private func archive(_ player: PlayerListItem) {
        attempt($error) { try ports?.commands.archivePlayer(player.id) }
    }

    /// ADR-0008: ask only when matches would go with them.
    private func requestRemoval(of player: PlayerListItem) {
        let count = ports?.list.matchCount(of: player.id) ?? 0
        if count > 0 {
            removal = Removal(player: player, matchCount: count)
        } else {
            attempt($error) { try ports?.commands.removePlayer(player.id) }
        }
    }
}

/// A pending `RemovePlayer` that needs confirming: the player and how many matches go with them.
struct Removal: Identifiable {
    let player: PlayerListItem
    let matchCount: Int
    var id: PlayerID { player.id }

    var title: String { "Remove \(player.name)?" }
    var message: String {
        "This permanently deletes \(player.name) and their \(matchCount) \(matchCount == 1 ? "match" : "matches")."
    }
}

extension View {
    /// The `RemovePlayer` confirmation (S42): runs the removal on confirm; a refusal lands in `error`.
    func removalConfirmation(_ removal: Binding<Removal?>, error: Binding<String?>, then done: @escaping () -> Void = {}) -> some View {
        modifier(RemovalConfirmation(removal: removal, error: error, done: done))
    }
}

private struct RemovalConfirmation: ViewModifier {
    @Binding var removal: Removal?
    @Binding var error: String?
    let done: () -> Void
    @Environment(\.playersPorts) private var ports

    func body(content: Content) -> some View {
        content.confirmationDialog(
            removal?.title ?? "", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
            titleVisibility: .visible, presenting: removal
        ) { pending in
            Button("Remove and Delete \(pending.matchCount == 1 ? "Match" : "Matches")", role: .destructive) {
                attempt($error) {
                    try ports?.commands.removePlayer(pending.player.id)
                    done()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }
}

/// `MergePlayers` (S33): pick the active player to keep; `foldedIn`'s matches and templates move to them.
struct MergePicker: View {
    let foldedIn: PlayerListItem
    @Environment(\.playersPorts) private var ports
    @Environment(\.dismiss) private var dismiss
    @State private var kept: PlayerListItem?
    @State private var error: String?

    var body: some View {
        let candidates = (ports?.list.players ?? []).filter { !$0.isArchived && $0.id != foldedIn.id }
        List {
            Section {
                ForEach(candidates) { player in
                    Button { kept = player } label: {
                        PlayerLabel(player: player)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("For two records of the same person. Everything \(foldedIn.name) played moves to the player you keep, and \(foldedIn.name) goes.")
            }
        }
        .overlay {
            if candidates.isEmpty {
                ContentUnavailableView("No One to Merge Into", systemImage: "person.2", description: Text("Add another player first."))
            }
        }
        .navigationTitle("Merge \(foldedIn.name) Into")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .confirmationDialog(
            "Merge \(foldedIn.name) into \(kept?.name ?? "")?",
            isPresented: Binding(get: { kept != nil }, set: { if !$0 { kept = nil } }),
            titleVisibility: .visible, presenting: kept
        ) { kept in
            Button("Merge") {
                attempt($error) {
                    try ports?.commands.mergePlayers(keep: kept.id, foldIn: foldedIn.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { kept in
            Text("\(foldedIn.name)'s matches and templates move to \(kept.name). This can't be undone.")
        }
        .errorAlert($error)
    }
}

/// Add or edit a player: name and colour from the fixed palette.
struct PlayerEditor: View {
    enum Mode: Identifiable {
        case add
        case edit(PlayerListItem)

        var id: String {
            if case .edit(let p) = self { p.id.uuidString } else { "add" }
        }
    }

    let mode: Mode
    @Environment(\.playersPorts) private var ports
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colour = PlayerColour.blue
    @State private var error: String?
    @State private var loaded = false
    /// The archived player holding the entered name, while offering to remove them.
    @State private var offeringRemoval: PlayerListItem?
    @State private var removal: Removal?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name).nameEntry().onSubmit(save)
            }
            // S22: colours are paid; while Free there is no picker and no plate (the colour is kept).
            if ports?.showsColours == true {
                Section("Colour") {
                    ColourGrid(selection: $colour)
                }
                Section {
                    PlayerPlate(name: name.isEmpty ? "Name" : name, colour: colour.color)
                        .font(.title3.weight(.semibold))
                } header: {
                    Text("Preview")
                }
            }
        }
        .navigationTitle(isAdd ? "New Player" : "Edit Player")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAdd ? "Add" : "Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert(
            "\(offeringRemoval?.name ?? "") is archived",
            isPresented: Binding(get: { offeringRemoval != nil }, set: { if !$0 { offeringRemoval = nil } }),
            presenting: offeringRemoval
        ) { holder in
            Button("Remove \(holder.name)", role: .destructive) { removeNameHolder(holder) }
            Button("Cancel", role: .cancel) {}
        } message: { holder in
            Text("Unarchive \(holder.name) instead, or remove them permanently to use the name.")
        }
        .removalConfirmation($removal, error: $error, then: save)
        .errorAlert($error)
        .onAppear(perform: load)
    }

    private var isAdd: Bool { if case .add = mode { true } else { false } }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .add: colour = PlayerColour.nextUnused(ports?.list.players.map(\.colour) ?? [])
        case .edit(let p): (name, colour) = (p.name, PlayerColour(rawValue: p.colour) ?? .gray)
        }
    }

    private func save() {
        guard let commands = ports?.commands else { return }
        do {
            switch mode {
            case .add:
                try commands.addPlayer(named: name, colour: colour.rawValue)
            case .edit(let p):
                if name != p.name { try commands.renamePlayer(p.id, to: name) }
                if colour.rawValue != p.colour { try commands.changePlayerColour(p.id, to: colour.rawValue) }
            }
            dismiss()
        } catch PlayerCommandError.nameHeldByArchivedPlayer(_, let archived) {
            // S2/S3/S32: the name is an archived player's; offer to remove them (S42).
            offeringRemoval = ports?.list.players.first { $0.id == archived }
            if offeringRemoval == nil { error = PlayerCommandError.unknownPlayer.localizedDescription }
        } catch let refused as UpgradeRequired {
            // S52: close the editor so the upgrade offer can show.
            dismiss()
            ports?.showUpgradeOffer(refused.feature)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Removes the archived name-holder (confirming first when they have matches), then retries the save.
    private func removeNameHolder(_ player: PlayerListItem) {
        let count = ports?.list.matchCount(of: player.id) ?? 0
        if count > 0 {
            removal = Removal(player: player, matchCount: count)
        } else {
            attempt($error) {
                try ports?.commands.removePlayer(player.id)
                save()
            }
        }
    }
}

/// The fixed player palette as 44 pt swatches.
struct ColourGrid: View {
    @Binding var selection: PlayerColour

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(PlayerColour.allCases, id: \.self) { c in
                Button { selection = c } label: {
                    Circle()
                        .fill(c.color)
                        .frame(width: 40, height: 40)
                        .overlay {
                            if c == selection {
                                Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.title)
                .accessibilityAddTraits(c == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Choose which player is Me (spec 012, `SetMe`).
public struct MeView: View {
    @Environment(\.playersPorts) private var ports
    @State private var error: String?

    public init() {}

    public var body: some View {
        let players = (ports?.list.players ?? []).filter { !$0.isArchived }
        List(players) { player in
            Button {
                attempt($error) { try ports?.commands.setMe(player.id) }
            } label: {
                HStack {
                    PlayerLabel(player: player)
                    Spacer()
                    if player.id == ports?.list.me?.id {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .frame(minHeight: 36)
            }
            .tint(.primary)
        }
        .navigationTitle("Me")
        .errorAlert($error)
    }
}
