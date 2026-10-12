import DesignSystem
import SwiftUI

/// History's last row while Free (S17): how many older matches are hidden. Tapping it opens the
/// upgrade offer (S52); the matches are kept and all appear on unlock.
struct HiddenMatchesRow: View {
    let count: Int
    let upgrade: () -> Void

    var body: some View {
        Button(action: upgrade) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? "1 older match hidden" : "\(count) older matches hidden")
                        .font(.subheadline.weight(.medium))
                    Text("Upgrade once, forever, to see your whole history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityHint("Shows the upgrade offer")
    }
}

/// A paid screen while Free (Stats, Series): what it would show, and a button back to the generic
/// upgrade offer (S52), which the screen also opens when it appears.
struct LockedFeatureView: View {
    let title: String
    let systemImage: String
    let message: String
    let upgrade: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Upgrade", action: upgrade)
                .buttonStyle(.borderedProminent)
        }
    }
}
