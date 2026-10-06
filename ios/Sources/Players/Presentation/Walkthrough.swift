import DesignSystem
import SwiftUI

/// One page of the walkthrough: a symbol, a title and a line or two.
struct WalkthroughPage: Identifiable, Hashable {
    let id: Int
    let symbol: String
    let title: String
    let detail: String

    /// How to run a match (S48), in the order you meet it at the table.
    static let all: [WalkthroughPage] = [
        WalkthroughPage(
            id: 0, symbol: "play.circle.fill", title: "Start a game",
            detail: "Tap New Game, pick the players and who breaks. Setups you've played become templates, so a rematch is one tap."),
        WalkthroughPage(
            id: 1, symbol: "plus.forwardslash.minus", title: "Score with + and −",
            detail: "Each player has one + and one −. Tap + when they win a frame; the break moves on by itself. − puts a mistake right."),
        WalkthroughPage(
            id: 2, symbol: "lock.iphone", title: "From the lock screen",
            detail: "A live match shows on the lock screen and in the Dynamic Island. Score with + or pause it there, without unlocking."),
        WalkthroughPage(
            id: 3, symbol: "hand.draw.fill", title: "Swipe to tidy up",
            detail: "Swipe a player to archive them, and an archived player to remove them. Swipe a template or a past match to delete it."),
        WalkthroughPage(
            id: 4, symbol: "chart.bar.xaxis", title: "History and stats",
            detail: "Every match lands in History. Stats and Series show who's ahead, head to head and over time."),
    ]
}

/// The walkthrough (spec 012, S48): a few short pages on running a match. Skippable from any page,
/// and replayable: Settings presents it again.
///
///     .sheet(isPresented: $replaying) { WalkthroughView { replaying = false } }
public struct WalkthroughView: View {
    private let onDone: () -> Void
    private let pages = WalkthroughPage.all
    @State private var index = 0

    /// `onDone` runs on Skip and on the last page's Done.
    public init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onDone)
                    .frame(minHeight: 44)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
                    .accessibilityHint("Closes the walkthrough")
            }
            .padding(.horizontal)

            pager

            Button(action: advance) {
                Text(isLast ? "Get Started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(24)
        }
    }

    private var isLast: Bool { index == pages.count - 1 }

    private func advance() {
        if isLast { onDone() } else { withAnimation { index += 1 } }
    }

    @ViewBuilder private var pager: some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(pages) { page in
                WalkthroughPageView(page: page, position: page.id + 1, count: pages.count).tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        #else
        WalkthroughPageView(page: pages[index], position: index + 1, count: pages.count)
        #endif
    }
}

private struct WalkthroughPageView: View {
    let page: WalkthroughPage
    let position: Int
    let count: Int
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 72

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: page.symbol)
                    .font(.system(size: symbolSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(minHeight: symbolSize * 1.3)
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(page.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 48)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(page.title). \(page.detail)")
            .accessibilityValue("Page \(position) of \(count)")
        }
    }
}

#Preview {
    WalkthroughView {}
}
