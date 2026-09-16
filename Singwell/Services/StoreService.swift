import Foundation
import Observation
import StoreKit

/// What Singwell Pro unlocks. Free stays genuinely useful; Pro removes the ceilings.
enum Entitlements {
    static let freeTakeLimit = 3
    static let freeQuestCount = 5
    static let freeWarmupSteps = 4

    static func canSaveTake(count: Int, pro: Bool) -> Bool { pro || count < freeTakeLimit }
    static func canUseRoutine(_ id: String, pro: Bool) -> Bool { pro || id == "quick" }
    static func canUseQuestCount(_ count: Int, pro: Bool) -> Bool { pro || count <= freeQuestCount }
    static func canUseDrill(_ drill: String, pro: Bool) -> Bool { pro || drill == "arpeggio" }
    static func canUseWarmupSteps(_ steps: Int, pro: Bool) -> Bool { pro || steps <= freeWarmupSteps }
}

enum ProductID {
    static let monthly = "live.singwell.pro.monthly"
    static let yearly = "live.singwell.pro.yearly"
    static let lifetime = "live.singwell.pro.lifetime"
    static let all = [monthly, yearly, lifetime]
}

/// StoreKit 2 wrapper. `isPro` is derived from current entitlements and refreshed on
/// launch, after purchases, and whenever a transaction update arrives.
@MainActor
@Observable
final class StoreService {
    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var loading = false
    var lastError: String?
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let fetched = try await Product.products(for: ProductID.all)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            lastError = "Could not load subscription options. Check your connection and try again."
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil { owned.insert(transaction.productID) }
        }
        purchasedProductIDs = owned
        isPro = !owned.isDisjoint(with: ProductID.all)
    }

    /// Returns true when the purchase completed. Pending (Ask to Buy) and cancelled return false without an error.
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    return true
                }
                lastError = "The purchase could not be verified."
                return false
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = "The purchase did not complete. Please try again."
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Restore did not complete. Please try again."
        }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    /// "1 week free" when the product carries a free introductory offer.
    func trialLabel(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let unit: String
        switch p.unit {
        case .day: unit = p.value == 1 ? "day" : "days"
        case .week: unit = p.value == 1 ? "week" : "weeks"
        case .month: unit = p.value == 1 ? "month" : "months"
        case .year: unit = p.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        return "\(p.value) \(unit) free"
    }
}
