import DesignSystem
import StatsApplication
import UpgradePublished
import SwiftUI

/// Stats (spec 014, S18, S19): `Stats(filter)` from Me's point of view (or a chosen player), grouped
/// by opponent and/or weekday. One group is in focus with its full figures; the rest are listed below
/// as context, and tapping one brings it into focus.
public struct StatsView: View {
    @Environment(\.statsPorts) private var ports
    @AppStorage("stats.grouping") private var groupingChoice = GroupingChoice.opponent.rawValue
    @AppStorage("stats.includeAbandoned") private var includeAbandoned = false
    @AppStorage("stats.includeArchived") private var includeArchived = false
    @State private var chosenPlayer: UUID?
    @State private var narrowing = Narrowing()
    @State private var focused: StatsGroup.Key?
    @State private var showingFilters = false

    public init() {}

    private var pointOfView: UUID? { chosenPlayer ?? ports?.me?() }
    private var grouping: GroupingChoice { GroupingChoice(rawValue: groupingChoice) ?? .opponent }

    private func filter(_ pov: UUID) -> StatsFilter {
        StatsFilter(
            pointOfView: pov, opponent: narrowing.opponent, weekday: narrowing.weekday, game: narrowing.game,
            style: narrowing.style, dates: narrowing.dates, includeAbandoned: includeAbandoned,
            includeArchivedPlayers: includeArchived, grouping: grouping.value)
    }

    public var body: some View {
        Group {
            if let query = ports?.stats, query.isStatsLocked {
                LockedFeatureView(
                    title: "Stats", systemImage: "chart.bar",
                    message: "Stats by opponent and by day of the week come with the upgrade. Every match you play is counted already.",
                    upgrade: upgrade)
            } else if let query = ports?.stats {
                if let pov = pointOfView {
                    content(query.stats(filter(pov)))
                } else {
                    choosePlayer(query)
                }
            } else {
                ContentUnavailableView("Stats", systemImage: "chart.bar", description: Text("Stats aren't available."))
            }
        }
        .navigationTitle("Stats")
        .onAppear { if isLocked { upgrade() } }
        .toolbar {
            if let query = ports?.stats, !query.isStatsLocked, pointOfView != nil {
                ToolbarItem(placement: .primaryAction) { pointOfViewMenu(query) }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingFilters = true } label: {
                        Label("Filter", systemImage: isFiltered
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            if let query = ports?.stats, let pov = pointOfView {
                StatsFilterSheet(
                    choices: query.statsChoices(for: pov, includeArchivedPlayers: includeArchived),
                    narrowing: $narrowing, grouping: $groupingChoice,
                    includeAbandoned: $includeAbandoned, includeArchived: $includeArchived)
            }
        }
        .onChange(of: groupingChoice) { focused = nil }
        .onChange(of: chosenPlayer) { focused = nil; narrowing.opponent = nil }
    }

    private var isFiltered: Bool { narrowing.isActive || includeAbandoned || includeArchived }

    /// Stats are paid (S18, S19): while Free the screen opens the generic upgrade offer (S52).
    private var isLocked: Bool { ports?.stats?.isStatsLocked ?? false }
    private func upgrade() { ports?.showUpgradeOffer(.stats) }

    // MARK: Content

    @ViewBuilder private func content(_ report: StatsReport) -> some View {
        if report.overall.matches == 0 {
            ContentUnavailableView(
                "No Matches Counted", systemImage: "chart.bar",
                description: Text(isFiltered
                    ? "No finished matches match these filters."
                    : "Finished matches \(report.pointOfView.map { "with \($0.name) " } ?? "")count here."))
        } else {
            let groups = report.groups
            let focus = groups.first { $0.id == focused } ?? groups.first
            List {
                Section {
                    if let focus {
                        FocusCard(title: title(focus), opponent: focus.opponent, figures: focus.figures, pointOfView: report.pointOfView)
                    } else {
                        FocusCard(title: "All matches", opponent: nil, figures: report.overall, pointOfView: report.pointOfView)
                    }
                } header: {
                    pointOfViewHeader(report)
                }

                if !groups.isEmpty {
                    Section(contextTitle) {
                        ForEach(groups.filter { $0.id != focus?.id }) { group in
                            Button { withAnimation { focused = group.id } } label: {
                                ContextRow(title: title(group), opponent: group.opponent, figures: group.figures)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows these figures in full")
                        }
                        ContextRow(title: "All matches", opponent: nil, figures: report.overall)
                    }
                }
            }
        }
    }

    private func pointOfViewHeader(_ report: StatsReport) -> some View {
        HStack(spacing: 6) {
            if let p = report.pointOfView {
                PlayerPlate(name: p.name, colour: p.plateColour, archived: p.isArchived)
                    .textCase(nil)
            }
            if let summary = narrowing.summary { Text("· " + summary).textCase(nil) }
        }
    }

    private var contextTitle: String {
        switch grouping {
        case .weekday: "Every weekday"
        case .both: "Every opponent and weekday"
        default: "Every opponent"
        }
    }

    private func title(_ group: StatsGroup) -> String {
        switch (group.opponent, group.weekday) {
        case let (o?, w?): "\(o.name) on \(w.plural)"
        case let (o?, nil): o.name
        case let (nil, w?): w.plural
        default: "All matches"
        }
    }

    // MARK: Point of view

    private func pointOfViewMenu(_ query: any StatsQuery) -> some View {
        Menu {
            Picker("Point of View", selection: Binding(get: { pointOfView }, set: { chosenPlayer = $0 == ports?.me?() ? nil : $0 })) {
                ForEach(query.statsPlayers(includeArchived: includeArchived)) { p in
                    Text(p.id == ports?.me?() ? "\(p.name) (Me)" : p.name).tag(Optional(p.id))
                }
            }
        } label: {
            Label("Point of View", systemImage: "person.crop.circle")
        }
    }

    @ViewBuilder private func choosePlayer(_ query: any StatsQuery) -> some View {
        let players = query.statsPlayers(includeArchived: includeArchived)
        if players.isEmpty {
            ContentUnavailableView("No Players Yet", systemImage: "person.2",
                                   description: Text("Add players and finish a match to see stats."))
        } else {
            List {
                Section {
                    ForEach(players) { p in
                        Button { chosenPlayer = p.id } label: {
                            PlayerPlate(name: p.name, colour: p.plateColour, archived: p.isArchived)
                        }
                    }
                } header: {
                    Text("Whose stats?")
                } footer: {
                    Text("Set who you are in Settings to open Stats on your own figures.")
                }
            }
        }
    }
}

// MARK: - Grouping and narrowing

enum GroupingChoice: Int, CaseIterable, Identifiable {
    case none, opponent, weekday, both

    var id: Int { rawValue }

    var value: StatsGrouping {
        switch self {
        case .none: []
        case .opponent: .opponent
        case .weekday: .weekday
        case .both: [.opponent, .weekday]
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .opponent: "Opponent"
        case .weekday: "Weekday"
        case .both: "Both"
        }
    }
}

/// The filters that narrow the matches (the toggles are remembered separately).
struct Narrowing: Equatable {
    var opponent: UUID?
    var opponentName: String?
    var weekday: Weekday?
    var game: String?
    var style: MatchRecord.Style?
    var styleText: String?
    var from: Date?
    var to: Date?

    var dates: DateInterval? {
        guard from != nil || to != nil else { return nil }
        let start = from.map { Calendar.current.startOfDay(for: $0) } ?? .distantPast
        let end = to.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) } ?? .distantFuture
        return DateInterval(start: start, end: max(start, end))
    }

    var isActive: Bool { opponent != nil || weekday != nil || game != nil || style != nil || dates != nil }

    /// "Asher · Fridays · Pool".
    var summary: String? {
        let parts = [opponentName, weekday?.plural, game.map(HistoryFormat.game), styleText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Grouping, filters and inclusion toggles, in a sheet.
struct StatsFilterSheet: View {
    let choices: StatsChoices
    @Binding var narrowing: Narrowing
    @Binding var grouping: Int
    @Binding var includeAbandoned: Bool
    @Binding var includeArchived: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Group By") {
                    Picker("Group By", selection: $grouping) {
                        ForEach(GroupingChoice.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Only") {
                    Picker("Opponent", selection: Binding(get: { narrowing.opponent }, set: { id in
                        narrowing.opponent = id
                        narrowing.opponentName = choices.opponents.first { $0.id == id }?.name
                    })) {
                        Text("Any").tag(UUID?.none)
                        ForEach(choices.opponents) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Weekday", selection: $narrowing.weekday) {
                        Text("Any").tag(Weekday?.none)
                        ForEach(Weekday.week, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("Game", selection: $narrowing.game) {
                        Text("Any").tag(String?.none)
                        ForEach(choices.games, id: \.self) { Text(HistoryFormat.game($0)).tag(Optional($0)) }
                    }
                    Picker("Match Style", selection: Binding(get: { narrowing.styleText }, set: { text in
                        narrowing.styleText = text
                        narrowing.style = choices.styles.first { $0.text == text }?.style
                    })) {
                        Text("Any").tag(String?.none)
                        ForEach(choices.styles) { Text($0.text).tag(Optional($0.text)) }
                    }
                }

                Section("Dates") {
                    optionalDate("From", $narrowing.from)
                    optionalDate("To", $narrowing.to)
                }

                Section {
                    Toggle("Include Abandoned", isOn: $includeAbandoned)
                    Toggle("Include Archived Players", isOn: $includeArchived)
                } footer: {
                    Text("Cancelled matches never count. Abandoned matches add frames and deciders, but no result.")
                }

                if narrowing.isActive {
                    Section {
                        Button("Clear Filters", role: .destructive) { narrowing = Narrowing() }
                    }
                }
            }
            .navigationTitle("Filter Stats")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func optionalDate(_ title: String, _ date: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(get: { date.wrappedValue != nil }, set: { date.wrappedValue = $0 ? .now : nil }))
        if let value = date.wrappedValue {
            DatePicker(title, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                .labelsHidden()
        }
    }
}

// MARK: - Figures

/// The rivalry in focus: W–D–L large, then every figure.
struct FocusCard: View {
    let title: String
    let opponent: HistoryPlayer?
    let figures: StatsFigures
    let pointOfView: HistoryPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if let opponent {
                    Text("v").foregroundStyle(.secondary)
                    PlayerPlate(name: title, colour: opponent.plateColour, archived: opponent.isArchived)
                        .font(.title3.weight(.semibold))
                } else {
                    Text(title).font(.title3.weight(.semibold))
                }
                Spacer()
                Text(StatsFormat.percent(figures.winPercentage))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Win rate \(StatsFormat.percent(figures.winPercentage))")
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                result(figures.won, "Won")
                result(figures.drawn, "Drawn")
                result(figures.lost, "Lost")
                if figures.abandoned > 0 { result(figures.abandoned, "Abandoned") }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                figure("Frames", StatsFormat.pair(figures.framesWon, figures.framesLost))
                figure("Deciders", StatsFormat.pair(figures.decidersWon, figures.decidersLost))
                figure("Match deciders", StatsFormat.pair(figures.matchDecidersWon, figures.matchDecidersLost))
                figure("Set deciders", StatsFormat.pair(figures.setDecidersWon, figures.setDecidersLost))
                figure("Avg frame", StatsFormat.time(figures.averageFrameTime))
                figure("Avg frame won", StatsFormat.time(figures.averageFrameTimeWon))
                figure("Avg frame lost", StatsFormat.time(figures.averageFrameTimeLost))
            }
            .font(.subheadline)
        }
        .padding(.vertical, 8)
    }

    private func result(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ScoreNumeral(value)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A group listed as context: name, W–D–L and win %.
struct ContextRow: View {
    let title: String
    let opponent: HistoryPlayer?
    let figures: StatsFigures

    var body: some View {
        HStack {
            if let opponent {
                PlayerPlate(name: title, colour: opponent.plateColour, archived: opponent.isArchived)
            } else {
                Text(title)
            }
            Spacer(minLength: 8)
            Text("\(figures.won)–\(figures.drawn)–\(figures.lost)")
                .monospacedDigit()
            Text(StatsFormat.percent(figures.winPercentage))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): won \(figures.won), drawn \(figures.drawn), lost \(figures.lost), win rate \(StatsFormat.percent(figures.winPercentage))")
    }
}

enum StatsFormat {
    static func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "–"
    }

    static func pair(_ a: Int, _ b: Int) -> String { "\(a)–\(b)" }

    static func time(_ t: TimeInterval?) -> String { t.map(clockText) ?? "–" }
}
