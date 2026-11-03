import SwiftUI

public struct ProPaywallView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var storeManager = StoreKitManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: storeManager.isProUnlocked ? "checkmark.seal.fill" : "seal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(CarTVTheme.accent)

                Text(storeManager.isProUnlocked ? "Pro is unlocked" : "DrivePlay Pro")
                    .font(.title2.weight(.bold))
                    .foregroundColor(CarTVTheme.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(CarTVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // The buy button only shows once the store offers the upgrade.
                if let product = storeManager.proProduct, !storeManager.isProUnlocked {
                    Button {
                        Task { await storeManager.purchase(product) }
                    } label: {
                        Text("Buy Pro · \(product.displayPrice)")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Restore Purchases") {
                    Task { await storeManager.restorePurchases() }
                }
                .font(.footnote)

                if let message = storeManager.lastErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(CarTVTheme.textSecondary)
                }
            }
            .padding()
            .navigationTitle("CarTV Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await storeManager.prepare() }
    }

    private var message: String {
        if storeManager.isProUnlocked {
            return "You have full, unlimited access to all DrivePlay features including unlimited streaming, offline vault, and car screen mirroring."
        }
        if storeManager.proProduct != nil {
            return "A one-time upgrade to DrivePlay Pro."
        }
        return "The Pro upgrade is not available in the store right now."
    }
}
