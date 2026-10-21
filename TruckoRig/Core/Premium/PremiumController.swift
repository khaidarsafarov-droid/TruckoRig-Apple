import Foundation
import Observation
import UserNotifications

enum PremiumCopy {
    static func locale(for language: AppLanguage) -> Locale {
        if let identifier = language.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return .autoupdatingCurrent
    }

    static func reminderBody(trialEnd: Date, price: String?, locale: Locale) -> String {
        let date = DateUtils.mediumDate(trialEnd, locale: locale)
        let shown = PremiumPolicy.displayPrice(price)
        return String(localized: "premium.reminder.body \(date) \(shown)", locale: locale)
    }
}

/// Premium entitlement, the one-time offer, and the three-day reminder.
@MainActor
@Observable
final class PremiumController {
    private let gateway: any PremiumGateway
    private let notifications: any TrialNotificationCenter
    private let store: PremiumLocalStore
    private let notificationDelegate = TrialNotificationDelegate()
    private var listen: Task<Void, Never>?

    private(set) var isActive = false
    private(set) var didRefresh = false
    private(set) var catalog = PremiumCatalog(displayPrice: nil, includesFreeMonth: true)
    private(set) var purchaseError: String?
    private(set) var revision = 0

    var now: () -> Date = Date.init
    var calendar = Calendar.current
    var localeProvider: () -> Locale = { .autoupdatingCurrent }

    init(
        gateway: any PremiumGateway,
        notifications: any TrialNotificationCenter,
        store: PremiumLocalStore
    ) {
        self.gateway = gateway
        self.notifications = notifications
        self.store = store
        notificationDelegate.onOpen = { [weak self] in
            Task { @MainActor in
                await self?.manage()
            }
        }
    }

    /// StoreKit-backed controller used by the running app.
    convenience init() {
        self.init(
            gateway: StoreKitPremiumGateway(),
            notifications: SystemTrialNotificationCenter(),
            store: PremiumLocalStore.standard()
        )
    }

    /// Does not start StoreKit. Previews and storage tests use this.
    convenience init(inactiveStore: PremiumLocalStore? = nil) {
        let defaults = UserDefaults(suiteName: "com.truckorig.premium.inactive") ?? .standard
        self.init(
            gateway: InactivePremiumGateway(),
            notifications: SystemTrialNotificationCenter(),
            store: inactiveStore ?? PremiumLocalStore(defaults: defaults)
        )
    }

    var displayPrice: String {
        PremiumPolicy.displayPrice(catalog.displayPrice ?? store.read().formattedPrice)
    }

    var includesFreeMonth: Bool {
        catalog.includesFreeMonth
    }

    var shouldShowFirstRun: Bool {
        _ = revision
        guard didRefresh else { return false }
        return PremiumPolicy.shouldPromptForSubscription(
            subscribed: isActive,
            offerAlreadyHandled: store.wasOfferHandled()
        )
    }

    var shouldShowBanner: Bool {
        _ = revision
        let decision = TrialReminderPolicy.decide(
            premiumActive: isActive,
            state: store.read(),
            now: now()
        )
        return decision.showBanner
    }

    var reminderText: String {
        let state = store.read()
        guard let end = state.trialEnd else { return "" }
        return PremiumCopy.reminderBody(trialEnd: end, price: state.formattedPrice ?? catalog.displayPrice, locale: localeProvider())
    }

    func start() {
        guard listen == nil else { return }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        listen = Task { [weak self] in
            await self?.refresh()
            guard let self else { return }
            for await _ in self.gateway.updates() {
                await self.refresh()
            }
        }
    }

    func refresh() async {
        let loaded = (try? await gateway.loadCatalog()) ?? catalog
        let entitlement = try? await gateway.currentEntitlement()
        await apply(entitlement: entitlement, catalog: loaded, now: now())
    }

    func apply(entitlement: PremiumEntitlement?, catalog: PremiumCatalog, now: Date) async {
        self.catalog = catalog
        didRefresh = true
        let price = catalog.displayPrice ?? entitlement?.displayPrice
        if let entitlement, entitlement.isActive {
            isActive = true
            markOfferHandled()
            let trialEnd = StoreKitTrialEnd.date(from: entitlement.facts)
            if let trialEnd, now < trialEnd {
                store.recordTrial(purchaseID: entitlement.purchaseID, trialEnd: trialEnd, price: price)
            } else {
                await cancelPendingReminder()
                store.clearActiveTrial()
            }
        } else {
            isActive = false
            await cancelPendingReminder()
            store.clearActiveTrial()
        }
        revision += 1
        await syncReminder(now: now)
    }

    func purchase() async {
        purchaseError = nil
        do {
            switch try await gateway.purchase() {
            case .success, .pending:
                markOfferHandled()
                await refresh()
            case .cancelled:
                break
            case .unavailable:
                purchaseError = String(localized: "premium.purchase.unavailable", locale: localeProvider())
            }
        } catch {
            purchaseError = String(localized: "premium.purchase.unavailable", locale: localeProvider())
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await gateway.restore()
            await refresh()
        } catch {
            purchaseError = String(localized: "premium.purchase.unavailable", locale: localeProvider())
        }
    }

    func manage() async {
        await gateway.showManageSubscriptions()
    }

    func declineFirstRun() {
        markOfferHandled()
    }

    func dismissBanner() {
        store.dismissBanner(store.read().purchaseID)
        revision += 1
    }

    func clearPurchaseError() {
        purchaseError = nil
    }

    private func markOfferHandled() {
        guard !store.wasOfferHandled() else { return }
        store.markOfferHandled()
        revision += 1
    }

    private func syncReminder(now: Date) async {
        let state = store.read()
        let decision = TrialReminderPolicy.decide(premiumActive: isActive, state: state, now: now)
        switch decision.work {
        case .cancel:
            await cancelPendingReminder()
            store.markScheduled(nil)
        case .keep:
            break
        case .enqueue:
            guard let trigger = decision.triggerAt, let end = state.trialEnd else { return }
            let granted = await permissionGranted()
            guard granted else { return }
            let locale = localeProvider()
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: trigger)
            do {
                try await notifications.add(
                    id: PremiumReminder.notificationID(purchaseID: state.purchaseID),
                    title: String(localized: "premium.reminder.title", locale: locale),
                    body: PremiumCopy.reminderBody(trialEnd: end, price: state.formattedPrice, locale: locale),
                    actionTitle: String(localized: "settings.premium.manage", locale: locale),
                    components: components
                )
                store.markScheduled(trigger)
                if decision.postNotification {
                    store.markNotified(state.purchaseID)
                }
            } catch {
                store.markScheduled(nil)
            }
        }
    }

    private func permissionGranted() async -> Bool {
        switch await notifications.authorization() {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await notifications.requestAuthorization()
        }
    }

    private func cancelPendingReminder() async {
        let purchaseID = store.read().purchaseID
        guard !purchaseID.isEmpty else { return }
        notifications.remove(identifiers: [PremiumReminder.notificationID(purchaseID: purchaseID)])
    }
}
