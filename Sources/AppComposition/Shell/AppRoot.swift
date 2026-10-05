import DesignSystem
import MatchesPresentation
import PlayersPresentation
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
            #if os(iOS)
            .fullScreenCover(isPresented: .constant(needsWelcome)) {
                WelcomeView().environment(\.playersPorts, container.playersPorts)
            }
            #endif
    }
}
