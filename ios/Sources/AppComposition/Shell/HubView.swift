import DesignSystem
import MatchesPresentation
import PlayersPresentation
import StatsApplication
import StatsPresentation
import SwiftUI

/// The hub (spec 022): root of one NavigationStack, large title, no tab bar.
struct HubView: View {
    @Environment(\.playersPorts) private var players
    @Environment(\.matchesPorts) private var matches
    @Environment(\.statsPorts) private var stats
    @State private var path = NavigationPath()
    let initialRoute: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: MatchRoute.newGame) {
                        Label("New Game", systemImage: "plus.circle.fill")
                            .font(.title3.weight(.semibold))
                            .padding(.vertical, 10)
                    }
                }

                LiveMatchesSection()

                Section {
                    row(.history, "History", "clock.arrow.circlepath")
                    row(.stats, "Stats", "chart.bar")
                    row(.series, "Series", "calendar")
                    row(.players, "Players", "person.2")
                    row(.settings, "Settings", "gearshape")
                }

                if let me = players?.list.me {
                    Section {
                        NavigationLink(value: HubDestination.me) {
                            HStack {
                                Label("Me", systemImage: "person.crop.circle")
                                Spacer()
                                PlayerPlate(name: me.name, colour: PlayerColour.color(me.colour))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Me, \(me.name)")
                    }
                }
            }
            .navigationTitle("Snooker Tracker")
            .navigationDestination(for: MatchRoute.self) { route in
                switch route {
                case .newGame:
                    NewGameView { id in
                        path = NavigationPath()
                        path.append(MatchRoute.live(id))
                    }
                case .live(let id):
                    LiveMatchView(matchID: id)
                }
            }
            .onAppear(perform: openInitialRoute)
            .navigationDestination(for: HubDestination.self) { destination in
                switch destination {
                case .players: PlayersView()
                case .settings: SettingsView()
                case .me: MeView()
                case .history: HistoryView()
                default: PlaceholderScreen(title: destination.title)
                }
            }
            .navigationDestination(for: StatsRoute.self) { route in
                switch route {
                case .match(let id): MatchDetailView(matchID: id)
                }
            }
        }
    }

    private func openInitialRoute() {
        switch initialRoute {
        case "live": if let id = matches?.live.liveMatches.first?.id { path.append(MatchRoute.live(id)) }
        case "live2": if let id = matches?.live.liveMatches.last?.id { path.append(MatchRoute.live(id)) }
        case "newGame": path.append(MatchRoute.newGame)
        case "players": path.append(HubDestination.players)
        case "settings": path.append(HubDestination.settings)
        case "history": path.append(HubDestination.history)
        case "match":
            path.append(HubDestination.history)
            if let id = stats?.history.pastMatches(PastMatchesFilter()).first?.id { path.append(StatsRoute.match(id)) }
        default: break
        }
    }

    private func row(_ destination: HubDestination, _ title: String, _ symbol: String) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: symbol)
        }
    }
}

enum HubDestination: Hashable {
    case history, stats, series, players, settings, me

    var title: String {
        switch self {
        case .history: "History"
        case .stats: "Stats"
        case .series: "Series"
        case .players: "Players"
        case .settings: "Settings"
        case .me: "Me"
        }
    }
}

/// Settings (specs 007, 012): inset grouped list of match defaults and Me.
struct SettingsView: View {
    @Environment(\.playersPorts) private var players

    var body: some View {
        Form {
            MatchDefaultsSection()
            Section("You") {
                NavigationLink(value: HubDestination.me) {
                    LabeledContent("Me", value: players?.list.me?.name ?? "Not set")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Coming soon. Matches you finish are kept for when this lands."))
            .navigationTitle(title)
    }
}
