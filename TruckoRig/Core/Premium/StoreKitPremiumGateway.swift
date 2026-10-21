import Foundation
import StoreKit
import UIKit

struct PremiumCatalog: Equatable, Sendable {
    var displayPrice: String?
    var includesFreeMonth: Bool
}

struct PremiumEntitlement: Equatable, Sendable {
    var isActive: Bool
    var purchaseID: String
    var facts: SubscriptionPeriodFacts
    var displayPrice: String?
}

enum PremiumPurchaseOutcome: Equatable {
    case success
    case cancelled
    case pending
    case unavailable
}

@MainActor
protocol PremiumGateway: AnyObject {
    func loadCatalog() async throws -> PremiumCatalog
    func currentEntitlement() async throws -> PremiumEntitlement?
    func purchase() async throws -> PremiumPurchaseOutcome
    func restore() async throws
    func showManageSubscriptions() async
    func updates() -> AsyncStream<Void>
}

/// Preview and test stand-in. Premium stays off and nothing is scheduled.
@MainActor
final class InactivePremiumGateway: PremiumGateway {
    func loadCatalog() async throws -> PremiumCatalog {
        PremiumCatalog(displayPrice: nil, includesFreeMonth: true)
    }

    func currentEntitlement() async throws -> PremiumEntitlement? { nil }

    func purchase() async throws -> PremiumPurchaseOutcome { .unavailable }

    func restore() async throws {}

    func showManageSubscriptions() async {}

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

/// StoreKit 2. The trial end is the transaction expiration, or the renewal date when that is all StoreKit sent.
@MainActor
final class StoreKitPremiumGateway: PremiumGateway {
    func loadCatalog() async throws -> PremiumCatalog {
        guard let product = try await product() else {
            return PremiumCatalog(displayPrice: nil, includesFreeMonth: false)
        }
        let intro = product.subscription?.introductoryOffer
        let freeMonth = intro?.paymentMode == .freeTrial || intro?.id == PremiumPolicy.freeMonthOfferID
        return PremiumCatalog(displayPrice: product.displayPrice, includesFreeMonth: freeMonth)
    }

    func currentEntitlement() async throws -> PremiumEntitlement? {
        let product = try await product()
        let price = product?.displayPrice
        if let subscription = product?.subscription {
            let statuses = try await subscription.status
            let mapped: [PremiumEntitlement] = statuses.compactMap { status in
                guard let transaction = try? status.transaction.payloadValue,
                      let renewal = try? status.renewalInfo.payloadValue else { return nil }
                return Self.entitlement(
                    state: status.state,
                    transaction: transaction,
                    renewalDate: renewal.renewalDate,
                    price: price
                )
            }
            if let trial = mapped.first(where: { $0.isActive && $0.facts.introductoryFreeTrial }) {
                return trial
            }
            if let active = mapped.first(where: \.isActive) {
                return active
            }
        }
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue,
                  transaction.productID == PremiumPolicy.productID else { continue }
            return Self.entitlement(
                state: .subscribed,
                transaction: transaction,
                renewalDate: nil,
                price: price
            )
        }
        return nil
    }

    func purchase() async throws -> PremiumPurchaseOutcome {
        guard let product = try await product() else { return .unavailable }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            return .success
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .unavailable
        }
    }

    func restore() async throws {
        try await AppStore.sync()
    }

    func showManageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if let transaction = try? result.payloadValue {
                        await transaction.finish()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func product() async throws -> Product? {
        try await Product.products(for: [PremiumPolicy.productID]).first
    }

    /// Copies StoreKit's dates. Does not add a month to the purchase date.
    private static func entitlement(
        state: Product.SubscriptionInfo.RenewalState,
        transaction: Transaction,
        renewalDate: Date?,
        price: String?
    ) -> PremiumEntitlement {
        let entitled: Bool
        switch state {
        case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
            entitled = true
        default:
            entitled = false
        }
        let facts = SubscriptionPeriodFacts(
            isEntitled: entitled,
            introductoryFreeTrial: isFreeTrial(transaction),
            transactionExpiration: transaction.expirationDate,
            renewalDate: renewalDate
        )
        return PremiumEntitlement(
            isActive: entitled,
            purchaseID: String(transaction.originalID),
            facts: facts,
            displayPrice: price
        )
    }

    private static func isFreeTrial(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            if let offer = transaction.offer {
                let introductory = offer.type == .introductory || offer.id == PremiumPolicy.freeMonthOfferID
                return introductory && offer.paymentMode == .freeTrial
            }
        }
        if transaction.offerType == .introductory {
            let mode = transaction.offerPaymentModeStringRepresentation?.uppercased()
            return mode == nil || mode == "FREE_TRIAL"
        }
        return transaction.offerID == PremiumPolicy.freeMonthOfferID
    }
}
