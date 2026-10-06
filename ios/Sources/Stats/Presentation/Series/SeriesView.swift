import DesignSystem
import StatsApplication
import SwiftUI

/// The Series application ports the Series screen uses, injected by the composition root.
public struct SeriesPorts: Sendable {
    public let list: any SeriesListQuery
    public let commands: any SeriesCommands
    /// `MonthlySummary(series, month)` (spec 017); nil hides the summary button on each row.
    public let summaries: (any MonthlySummaryQuery)?

    public init(list: any SeriesListQuery, commands: any SeriesCommands, summaries: (any MonthlySummaryQuery)? = nil) {
        self.list = list
        self.commands = commands
        self.summaries = summaries
    }
}

public extension EnvironmentValues {
    @Entry var seriesPorts: SeriesPorts? = nil
}

/// The Series screen (spec 016), from `SeriesList`: tap a series to edit it in a sheet, + to create
/// one, swipe to delete (icon-only) with a confirmation that its matches are kept. The chart button
/// on a row opens its monthly summary (spec 017).
public struct SeriesView: View {
    @Environment(\.seriesPorts) private var ports
    @State private var editing: SeriesDraft?
    @State private var summaryFor: UUID?
    @State private var deleting: SeriesRow?
    @State private var error: String?

    public init() {}

    public var body: some View {
        let rows = ports?.list.series ?? []
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Series Yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("A series groups setups, like \u{201C}Fridays with Asher\u{201D}. Every match with one of its setups belongs to it, past and future.")
                } actions: {
                    Button("New Series") { editing = SeriesDraft() }
                }
            } else {
                List {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Button { editing = SeriesDraft(row) } label: { SeriesRowView(row: row) }
                                .tint(.primary)
                                .buttonStyle(.borderless)
                            if ports?.summaries != nil {
                                Button("Monthly Summary", systemImage: "chart.bar.doc.horizontal") { summaryFor = row.id }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityHint("Shows last month for \(row.name)")
                            }
                        }
                        .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = row }
                                    .labelStyle(.iconOnly)
                            }
                    }
                }
            }
        }
        .navigationTitle("Series")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Series", systemImage: "plus") { editing = SeriesDraft() }
            }
        }
        .onAppear { ports?.list.refresh() }
        .navigationDestination(item: $summaryFor) { id in
            MonthlySummaryView(series: id)
        }
        .sheet(item: $editing) { draft in
            SeriesEditor(draft: draft)
        }
        .confirmationDialog("Delete this series?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { row in
            Button("Delete Series", role: .destructive) {
                attempt($error) { try ports?.commands.deleteSeries(row.id) }
            }
        } message: { row in
            Text("\u{201C}\(row.name)\u{201D} is deleted. Its matches are kept, in History and in the stats.")
        }
        .errorAlert($error)
    }
}

/// A series row: name, then its setups' players.
struct SeriesRowView: View {
    let row: SeriesRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name).font(.headline)
            if row.setups.isEmpty {
                Text("No setups").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.setups.isEmpty ? "no setups" : summary)")
        .accessibilityHint("Edits this series")
        .accessibilityAddTraits(.isButton)
    }

    private var summary: String {
        let n = row.setups.count
        let pairings = Array(Set(row.setups.map(\.title))).sorted().joined(separator: ", ")
        return "\(n) setup\(n == 1 ? "" : "s") · \(pairings)"
    }
}

/// What the sheet edits: nil `id` creates a new series.
struct SeriesDraft: Identifiable {
    let id: UUID
    let seriesID: UUID?
    var name: String
    var setups: [SetupChoice]

    init() { id = UUID(); seriesID = nil; name = ""; setups = [] }
    init(_ row: SeriesRow) { id = row.id; seriesID = row.id; name = row.name; setups = row.setups }
}

/// Create / edit sheet: a name and one or more setups chosen from those already played.
struct SeriesEditor: View {
    @Environment(\.seriesPorts) private var ports
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SeriesDraft
    @State private var error: String?

    init(draft: SeriesDraft) { _draft = State(initialValue: draft) }

    private var isNew: Bool { draft.seriesID == nil }
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.setups.isEmpty
    }

    var body: some View {
        let choices = ports?.list.setupChoices(including: draft.setups) ?? draft.setups
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Fridays with Asher"))
                        .nameEntry()
                } header: {
                    Text("Name")
                }
                Section {
                    if choices.isEmpty {
                        Text("Setups appear here once a match has been played with them.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(choices) { choice in
                        SetupToggleRow(choice: choice, isOn: binding(for: choice))
                    }
                } header: {
                    Text("Setups")
                } footer: {
                    Text("Every match with one of these setups belongs to the series, past and future. A setup can be in several series.")
                }
            }
            .navigationTitle(isNew ? "New Series" : "Edit Series")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .errorAlert($error)
        }
    }

    private func binding(for choice: SetupChoice) -> Binding<Bool> {
        Binding {
            draft.setups.contains { $0.setup == choice.setup }
        } set: { on in
            if on {
                if !draft.setups.contains(where: { $0.setup == choice.setup }) { draft.setups.append(choice) }
            } else {
                draft.setups.removeAll { $0.setup == choice.setup }
            }
        }
    }

    private func save() {
        guard let commands = ports?.commands else { return }
        do {
            if let id = draft.seriesID {
                try commands.changeSeries(id, name: draft.name, setups: draft.setups)
            } else {
                try commands.createSeries(name: draft.name, setups: draft.setups)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One setup to tick: both players' plates and the details.
struct SetupToggleRow: View {
    let choice: SetupChoice
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        PlayerPlate(name: choice.first.name, colour: PlayerColour.color(choice.first.colour), archived: choice.first.isArchived)
                        Text("v").font(.subheadline).foregroundStyle(.secondary)
                        PlayerPlate(name: choice.second.name, colour: PlayerColour.color(choice.second.colour), archived: choice.second.isArchived)
                    }
                    .font(.body.weight(.semibold))
                    Text(choice.details).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.title), \(choice.details)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
