import OSLog
import SwiftUI

struct ProUpgradeSheet: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    private let logger = Logger(subsystem: "FormationFlow", category: "ProUpgrade")
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseState: PurchaseState = .idle

    enum PurchaseState {
        case idle
        case loading
        case pending
        case error(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Unlock FormationFlow Pro")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                featureRow("Unlimited formations")
                featureRow("Athlete roles & colors")
                featureRow("Timing controls")
                featureRow("Advanced path waypoints")
                featureRow("Multiple routines (soon)")
            }
            .padding(.horizontal, 32)

            Spacer()

            if case .pending = purchaseState {
                Label("Waiting for approval", systemImage: "clock")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 14)
            } else {
                if case .error(let message) = purchaseState {
                    Text(message)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button {
                    Task { await handlePurchase() }
                } label: {
                    if case .loading = purchaseState {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        let buttonText = {
                            if case .error(_) = purchaseState {
                                return "Try Again — $4.99"
                            }
                            return "Upgrade — $4.99"
                        }()
                        Text(buttonText)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled({
                    if case .loading = purchaseState { return true }
                    return false
                }())
                .accessibilityLabel(
                    {
                        if case .loading = purchaseState { return "Upgrading" }
                        if case .error(_) = purchaseState { return "Try Again" }
                        return "Upgrade"
                    }()
                )
            }

            Button("Restore Purchase") {
                Task {
                    await entitlementManager.restore()
                    if entitlementManager.isPro { dismiss() }
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)

            Text("One-time purchase. No subscription.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onChange(of: entitlementManager.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private func featureRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundColor(.primary)
    }

    private func handlePurchase() async {
        purchaseState = .loading
        do {
            let result = try await entitlementManager.purchase()
            switch result {
            case .success:
                break
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .failed:
                purchaseState = .error("Purchase could not be completed.")
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription, privacy: .private)")
            purchaseState = .error("Something went wrong. Please try again.")
        }
    }
}
