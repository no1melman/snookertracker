import DesignSystem
import PlayersApplication
import SwiftUI

/// The Players application ports a view may use, injected by the composition root.
public struct PlayersPorts: Sendable {
    public let list: any PlayersListQuery
    public let commands: any PlayerCommands

    public init(list: any PlayersListQuery, commands: any PlayerCommands) {
        self.list = list
        self.commands = commands
    }
}

public extension EnvironmentValues {
    @Entry var playersPorts: PlayersPorts? = nil
}

/// The Players screen (spec 011): Active and Archived sections, add, rename, change colour.
public struct PlayersView: View {
    @Environment(\.playersPorts) private var ports
    @State private var editing: PlayerEditor.Mode?

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
            Button("Add Player", systemImage: "plus") { editing = .add }
        }
        .sheet(item: $editing) { mode in
            NavigationStack { PlayerEditor(mode: mode) }
        }
    }

    private func row(_ player: PlayerListItem) -> some View {
        Button { editing = .edit(player) } label: {
            HStack {
                PlayerPlate(name: player.name, colour: PlayerColour.color(player.colour), archived: player.isArchived)
                if player.id == ports?.list.me?.id {
                    Text("Me").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .frame(minHeight: 36)
        }
        .tint(.primary)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { editing = .edit(player) }
            Button("Colour", systemImage: "paintpalette") { editing = .edit(player) }
        }
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

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name).nameEntry().onSubmit(save)
            }
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
        .navigationTitle(isAdd ? "New Player" : "Edit Player")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAdd ? "Add" : "Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
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
        attempt($error) {
            switch mode {
            case .add:
                try commands.addPlayer(named: name, colour: colour.rawValue)
            case .edit(let p):
                if name != p.name { try commands.renamePlayer(p.id, to: name) }
                if colour.rawValue != p.colour { try commands.changePlayerColour(p.id, to: colour.rawValue) }
            }
            dismiss()
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
                    PlayerPlate(name: player.name, colour: PlayerColour.color(player.colour))
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

/// First launch (spec 012): ask for your name, which creates Me.
public struct WelcomeView: View {
    @Environment(\.playersPorts) private var ports
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Welcome").font(.largeTitle.bold())
                Text("Scores, rivalries and history for the games you play with friends.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            TextField("Your name", text: $name)
                .nameEntry()
                .font(.title3)
                .padding()
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .onSubmit(save)
            Spacer()
            Button(action: save) {
                Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(24)
        .errorAlert($error)
        .onAppear { focused = true }
    }

    private func save() {
        guard let commands = ports?.commands, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        attempt($error) {
            let id = try commands.addPlayer(named: name, colour: PlayerColour.blue.rawValue)
            try commands.setMe(id)
        }
    }
}
