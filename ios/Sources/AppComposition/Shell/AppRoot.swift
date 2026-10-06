import DesignSystem
import iOSAdapters
import MatchesPresentation
import PlayersPresentation
import StatsPresentation
import SwiftUI

/// The app's root view: wires the ports into the environment and shows Welcome until Me exists.
public struct AppRoot: View {
    @State private var container = AppContainer.shared

    public init() {}

    private var initialRoute: String? {
        #if DEBUG
        return container.demoRoute
        #else
        return nil
        #endif
    }

    public var body: some View {
        let needsWelcome = container.players.me == nil
        HubView(initialRoute: initialRoute)
            .environment(\.matchesPorts, container.matchesPorts)
            .environment(\.playersPorts, container.playersPorts)
            .environment(\.statsPorts, container.statsPorts)
            .environment(\.seriesPorts, container.seriesPorts)
            .environment(\.matchDetailActions, container.matchDetailActions)
            .environment(\.archivePlayer, container.archivePlayer)
            .recordsAppLifecycle(container.lifecycle)
            #if os(iOS)
            .fullScreenCover(isPresented: .constant(needsWelcome)) {
                WelcomeView().environment(\.playersPorts, container.playersPorts)
            }
            #endif
    }
}
