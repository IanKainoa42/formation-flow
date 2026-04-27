import OSLog
import SwiftUI

struct ProUpgradeSheet: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    private let logger = Logger(subsystem: "FormationFlow", category: "ProUpgrade")
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseState: PurchaseState = .idle
    @State private var isRestoring = false
    @State private var restoreAlertMessage: String?

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
                featureRow("Multiple routines")
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
                    HStack(spacing: 8) {
                        if case .loading = purchaseState {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        let buttonText = {
                            if case .loading = purchaseState {
                                return "Upgrading..."
                            }
                            if case .error(_) = purchaseState {
                                return "Try Again — $4.99"
                            }
                            return "Upgrade — $4.99"
                        }()
                        Text(buttonText)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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
                .accessibilityHint(
                    {
                        if case .loading = purchaseState { return "Upgrading to Pro version" }
                        if case .error(_) = purchaseState { return "Try upgrading to Pro version again" }
                        return "Upgrade to Pro version"
                    }()
                )
                .help(
                    {
                        if case .loading = purchaseState { return "Upgrading" }
                        if case .error(_) = purchaseState { return "Try Again" }
                        return "Upgrade"
                    }()
                )
            }

            Button {
                Task {
                    isRestoring = true
                    await entitlementManager.restore()
                    isRestoring = false
                    if entitlementManager.isPro {
                        dismiss()
                    } else {
                        restoreAlertMessage = "No prior purchases were found on this Apple ID."
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if isRestoring {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    Text(isRestoring ? "Restoring Purchase..." : "Restore Purchase")
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
            .disabled({
                if case .loading = purchaseState { return true }
                return isRestoring
            }())
            .accessibilityLabel(isRestoring ? "Restoring Purchase" : "Restore Purchase")
            .accessibilityHint(isRestoring ? "Currently restoring previous purchases" : "Restore previous purchases")
            .help(isRestoring ? "Restoring Purchase" : "Restore Purchase")

            Text("One-time purchase. No subscription.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onChange(of: entitlementManager.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .alert(
            "Restore Purchases",
            isPresented: Binding(
                get: { restoreAlertMessage != nil },
                set: { if !$0 { restoreAlertMessage = nil } }
            ),
            presenting: restoreAlertMessage
        ) { _ in
            Button("OK", role: .cancel) { restoreAlertMessage = nil }
        } message: { message in
            Text(message)
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
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Something went wrong. Please try again."
            purchaseState = .error(message)
        }
    }
}
