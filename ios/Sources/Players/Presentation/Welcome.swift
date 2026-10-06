import DesignSystem
import PlayersApplication
import SwiftUI

/// First launch (spec 012, S48): a full-screen name entry that creates the player, then the skippable
/// walkthrough. Me is set when the walkthrough is done or skipped, which is what dismisses the welcome
/// (the composition root shows it while Me is unset).
public struct WelcomeView: View {
    @Environment(\.playersPorts) private var ports
    @State private var name = ""
    /// The player the name step created (or found); the walkthrough is showing once this is set.
    @State private var player: PlayerID?
    @State private var error: String?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 64

    public init() {}

    public var body: some View {
        Group {
            if let player {
                WalkthroughView { finish(as: player) }
                    .transition(.move(edge: .trailing))
            } else {
                nameEntry.transition(.move(edge: .leading))
            }
        }
        .animation(.default, value: player)
        .errorAlert($error)
    }

    private var isBlank: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var nameEntry: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: symbolSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Welcome")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Scores, rivalries and history for the games you play with friends.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's your name?").font(.headline)
                    TextField("Your name", text: $name)
                        .nameEntry()
                        .font(.title3)
                        .padding()
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .focused($focused)
                        .onSubmit(next)
                        .accessibilityLabel("Your name")
                    Text("You'll be Me on this phone. You can change it in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .padding(.top, 32)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: next) {
                Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBlank)
            .padding(24)
            .background(.bar)
        }
        .onAppear { focused = true }
    }

    /// The name step: creates the player (or takes the one an interrupted welcome created).
    private func next() {
        guard let ports, !isBlank else { return }
        attempt($error) {
            let colour = PlayerColour.nextUnused(ports.list.players.map(\.colour)).rawValue
            player = try Welcome.player(named: name, colour: colour, list: ports.list, commands: ports.commands)
        }
        if player != nil { focused = false }
    }

    /// Done or skipped: set Me, which ends the welcome.
    private func finish(as player: PlayerID) {
        guard let commands = ports?.commands else { return }
        attempt($error) { try commands.setMe(player) }
    }
}

#Preview {
    WelcomeView()
}
