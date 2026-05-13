import OSLog
import StoreKit
import SwiftUI

struct ProUpgradeSheet: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    private let logger = Logger(subsystem: "FormationFlow", category: "ProUpgrade")
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseState: PurchaseState = .idle
    @State private var isRestoring = false
    @State private var restoreAlertMessage: String?
    @State private var product: Product?

    enum PurchaseState {
        case idle
        case loading
        case pending
        case error(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Close")
                .help("Close")
            }

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
                    purchaseButtonLabel
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

            // DEBUG UNLOCK
            #if DEBUG
            Button("DEBUG: FORCE UNLOCK PRO") {
                Task {
                    await entitlementManager.debugForceProStatus()
                }
            }
            .font(.caption.bold())
            .foregroundColor(.green)
            .padding(.top, 4)
            
            Button("DEBUG: RESET PRO (Test Purchase)") {
                Task {
                    await entitlementManager.debugResetProStatus()
                }
            }
            .font(.caption.bold())
            .foregroundColor(.red)
            .padding(.top, 2)
            #endif

            Spacer()
        }
        .padding()
        .onChange(of: entitlementManager.isPro) { _, isPro in
            logger.info("isPro changed to: \(isPro)")
            if isPro { dismiss() }
        }
        .onAppear {
            logger.info("📱 ProUpgradeSheet appeared. isPro = \(entitlementManager.isPro)")
            if entitlementManager.isPro { dismiss() }
        }
        .onDisappear {
            logger.info("👋 ProUpgradeSheet disappeared")
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
        .task {
            do {
                let products = try await Product.products(for: [EntitlementManager.productID])
                product = products.first
            } catch {
                logger.error("Failed to load product: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private var purchaseButtonLabel: some View {
        let priceSuffix = product.map { " — \($0.displayPrice)" } ?? ""
        let buttonText = purchaseButtonText(priceSuffix: priceSuffix)
        
        return HStack(spacing: 8) {
            if case .loading = purchaseState {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            Text(buttonText)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
    
    private func purchaseButtonText(priceSuffix: String) -> String {
        if case .loading = purchaseState {
            return "Upgrading..."
        }
        if case .error(_) = purchaseState {
            return "Try Again\(priceSuffix)"
        }
        return "Upgrade\(priceSuffix)"
    }
    
    private func featureRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundColor(.primary)
    }

    private func handlePurchase() async {
        logger.info("🛒 User tapped Upgrade button")
        purchaseState = .loading
        do {
            logger.info("💳 Calling entitlementManager.purchase()...")
            let result = try await entitlementManager.purchase()
            logger.info("✅ Purchase call returned")
            switch result {
            case .success:
                logger.info("🎉 Purchase succeeded")
                break
            case .userCancelled:
                logger.info("❌ Purchase cancelled by user")
                purchaseState = .idle
            case .pending:
                logger.info("⏳ Purchase pending")
                purchaseState = .pending
            case .failed:
                logger.error("❌ Purchase failed")
                purchaseState = .error("Purchase could not be completed.")
            }
        } catch {
            logger.error("💥 Purchase threw error: \(error.localizedDescription, privacy: .public)")
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Something went wrong. Please try again."
            purchaseState = .error(message)
        }
    }
}
