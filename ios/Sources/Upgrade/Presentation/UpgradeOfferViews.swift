import SwiftUI
import UpgradeApplication
import UpgradePublished

// MARK: - In place (S52: templates, pause)

/// The in-place "Upgrade now" prompt (S52): embed it where a paid feature would be (the templates
/// area on New Game, the pause button) while the edition is Free. Tapping it opens the offer screen.
/// It draws nothing once the edition is Unlocked, so it can stay in the hierarchy.
public struct UpgradeNowPrompt: View {
    public enum Style: Sendable {
        /// A list row: lock, the feature's one-line message, and "Upgrade now".
        case row
        /// A compact bordered button, for where a control would be (the pause button).
        case button
    }

    @Environment(\.upgradePorts) private var ports
    @State private var showingOffer = false
    private let feature: PaidFeature
    private let style: Style

    public init(_ feature: PaidFeature, style: Style = .row) {
        self.feature = feature
        self.style = style
    }

    public var body: some View {
        if let ports, ports.isFree {
            prompt
                .sheet(isPresented: $showingOffer) {
                    UpgradeOfferScreen(feature: feature).environment(\.upgradePorts, ports)
                }
        }
    }

    @ViewBuilder private var prompt: some View {
        switch style {
        case .row:
            Button { showingOffer = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(feature.offerMessage)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text("Upgrade now")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(feature.offerMessage) Upgrade now")
        case .button:
            Button { showingOffer = true } label: {
                Label("Upgrade now", systemImage: "lock.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityHint(feature.offerMessage)
        }
    }
}

// MARK: - Generic screen (S52: every other paid feature)

public extension View {
    /// Presents the offer screen whenever `router` holds a request, and clears
    /// the request when it closes. Attach once, near the root, inside the `upgradePorts` environment.
    /// `.inPlace` features draw their own "Upgrade now" prompt where the feature would be; tapping it lands here.
    func upgradeOfferPresentation(_ router: UpgradeOfferRouter) -> some View {
        modifier(UpgradeOfferPresenter(router: router))
    }
}

private struct UpgradeOfferPresenter: ViewModifier {
    let router: UpgradeOfferRouter

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { router.request },
            set: { if $0 == nil { router.dismiss() } }
        )) { request in
            UpgradeOfferScreen(feature: request.feature)
        }
    }
}
