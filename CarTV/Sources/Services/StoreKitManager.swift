import Foundation
import StoreKit

/// The in-app purchase layer.
///
/// Nothing in the app is gated behind Pro today — every feature is unlocked.
/// The purchase flow is real all the same, so a bought upgrade survives a
/// reinstall and the entitlement is known without asking the store again.
@MainActor
public final class StoreKitManager: ObservableObject {
    public static let shared = StoreKitManager()

    /// The identifier of the Pro upgrade.
    public static let proProductID = "com.rushabh.cartvv.pro"

    /// Whether the account is entitled to Pro.
    @Published public private(set) var isProUnlocked: Bool = false
    /// The products the store offers for this app.
    @Published public private(set) var products: [Product] = []
    /// The last error the store reported, if any.
    @Published public private(set) var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    public init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// The Pro product, if the store offers it.
    public var proProduct: Product? {
        products.first { $0.id == Self.proProductID }
    }

    /// Loads the products of the store and the purchases of this account.
    public func prepare() async {
        do {
            products = try await Product.products(for: [Self.proProductID])
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            products = []
        }
        await refreshEntitlements()
    }

    /// Buys a product and finishes its transaction.
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try checkVerified(result)
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Restores the purchases of this account.
    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    /// Reads the purchases this account is entitled to.
    public func refreshEntitlements() async {
        var productIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            productIDs.insert(transaction.productID)
        }
        isProUnlocked = Self.unlocksPro(transactionIDs: productIDs)
    }

    /// Whether the given purchased products unlock Pro.
    public static func unlocksPro(transactionIDs: Set<String>, productID: String = proProductID) -> Bool {
        transactionIDs.contains(productID)
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(update) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
