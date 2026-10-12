import SwiftUI
import UpgradeApplication
import UpgradePublished

/// The benefits screen (S53), which is also the generic upgrade offer (S52): everything the one-off
/// purchase unlocks, in plain language, the localised price, Buy (S49) and Restore (S50). Closes by
/// itself once the edition is Unlocked. Pass `feature` when a refused paid feature opened it.
public struct BenefitsScreen: View {
    @Environment(\.upgradePorts) private var ports
    private let feature: PaidFeature?

    public init(feature: PaidFeature? = nil) { self.feature = feature }

    public var body: some View {
        if let ports {
            BenefitsContent(ports: ports, feature: feature)
        } else {
            ContentUnavailableView("Upgrade Unavailable", systemImage: "lock")
        }
    }
}

/// `BenefitsScreen` in its own navigation stack with a Close button: how the generic offer and the
/// in-place prompt present it.
public struct UpgradeOfferScreen: View {
    @Environment(\.dismiss) private var dismiss
    private let feature: PaidFeature?

    public init(feature: PaidFeature? = nil) { self.feature = feature }

    public var body: some View {
        NavigationStack {
            BenefitsScreen(feature: feature)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

private struct BenefitsContent: View {
    let ports: UpgradePorts
    let feature: PaidFeature?
    @State private var model: BenefitsScreenModel
    @Environment(\.dismiss) private var dismiss

    init(ports: UpgradePorts, feature: PaidFeature?) {
        self.ports = ports
        self.feature = feature
        _model = State(initialValue: BenefitsScreenModel(commands: ports.commands, edition: ports.edition))
    }

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if let feature {
                Section {
                    Label(feature.offerMessage, systemImage: "lock.fill")
                        .foregroundStyle(.primary)
                }
            }

            Section {
                ForEach(UpgradeBenefit.all) { benefit in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                            if let free = benefit.freeAllows {
                                Text(free)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: benefit.systemImage)
                            .foregroundStyle(.tint)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Everything in the full version")
            } footer: {
                Text(UpgradeBenefit.freeNote)
            }
        }
        .navigationTitle("Upgrade")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { purchaseBar }
        .task { await model.loadPrice() }
        .onChange(of: ports.isFree) { _, isFree in model.editionChanged(isFree: isFree) }
        .onChange(of: model.phase) { _, phase in
            if phase == .unlocked { dismiss() }
        }
        .alert(
            model.message ?? "",
            isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if model.message == BenefitsScreenModel.nothingToRestore {
                Text("The App Store has no purchase of the full version for this Apple Account.")
            } else {
                Text("Check your connection and try again.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Upgrade once, forever, to unlock")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("One purchase unlocks everything on this device. Not a subscription. Family Sharing included.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    private var buyTitle: String {
        model.price.map { "Upgrade once, unlock forever · \($0)" } ?? "Upgrade once, unlock forever"
    }

    private var purchaseBar: some View {
        VStack(spacing: 12) {
            if model.phase == .waitingForApproval {
                VStack(spacing: 2) {
                    Label("Waiting for approval", systemImage: "hourglass")
                        .font(.headline)
                    Text("It unlocks by itself once the purchase is approved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    Task { await model.buy() }
                } label: {
                    HStack(spacing: 8) {
                        if model.phase == .purchasing { ProgressView() }
                        Text(buyTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy)
            }

            Button {
                Task { await model.restore() }
            } label: {
                HStack(spacing: 8) {
                    if model.phase == .restoring { ProgressView() }
                    Text("Restore Purchase")
                }
            }
            .disabled(model.isBusy)
        }
        .padding()
        .background(.bar)
    }
}
