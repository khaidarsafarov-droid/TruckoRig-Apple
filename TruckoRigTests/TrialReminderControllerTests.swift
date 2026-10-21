import UserNotifications
import XCTest
@testable import TruckoRig

@MainActor
final class TrialReminderControllerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var notifications: FakeTrialNotifications!
    private var controller: PremiumController!
    private let trialEnd = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    override func setUp() async throws {
        suiteName = "com.truckorig.premium.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        notifications = FakeTrialNotifications()
        controller = PremiumController(
            gateway: FakePremiumGateway(),
            notifications: notifications,
            store: PremiumLocalStore(defaults: defaults)
        )
        controller.calendar = calendar
        controller.localeProvider = { Locale(identifier: "en") }
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        controller = nil
        defaults = nil
    }

    func testDoesNotScheduleWithoutPermission() async {
        notifications.permission = .denied
        await controller.apply(
            entitlement: trialEntitlement(),
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: trialEnd.addingTimeInterval(-10 * 86_400)
        )
        XCTAssertTrue(notifications.added.isEmpty)
        XCTAssertEqual(notifications.authorizationRequests, 0)
    }

    func testDoesNotScheduleWhenThePromptIsDeclined() async {
        notifications.permission = .notDetermined
        notifications.grant = false
        await controller.apply(
            entitlement: trialEntitlement(),
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: trialEnd.addingTimeInterval(-10 * 86_400)
        )
        XCTAssertEqual(notifications.authorizationRequests, 1)
        XCTAssertTrue(notifications.added.isEmpty)
    }

    func testSchedulesOneCalendarNotificationPerPurchase() async {
        notifications.permission = .authorized
        let now = trialEnd.addingTimeInterval(-10 * 86_400)
        let catalog = PremiumCatalog(displayPrice: "2,99 €", includesFreeMonth: true)
        await controller.apply(entitlement: trialEntitlement(), catalog: catalog, now: now)
        await controller.apply(entitlement: trialEntitlement(), catalog: catalog, now: now)

        XCTAssertEqual(notifications.added.count, 1)
        let request = notifications.added[0]
        XCTAssertEqual(request.id, "truckorig.trial.1001")
        XCTAssertFalse(request.repeats)
        let trigger = TrialReminderPolicy.triggerDate(trialEnd: trialEnd)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: trigger)
        XCTAssertEqual(request.components.year, parts.year)
        XCTAssertEqual(request.components.month, parts.month)
        XCTAssertEqual(request.components.day, parts.day)
        XCTAssertEqual(request.components.hour, parts.hour)
        XCTAssertEqual(request.components.minute, parts.minute)
        XCTAssertTrue(request.body.contains("2,99 €"))
        XCTAssertFalse(request.body.contains("Google Play"))
    }

    func testCancelsTheNotificationWhenTheTrialEnds() async {
        notifications.permission = .authorized
        await controller.apply(
            entitlement: trialEntitlement(),
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: trialEnd.addingTimeInterval(-10 * 86_400)
        )
        XCTAssertEqual(notifications.added.count, 1)

        await controller.apply(
            entitlement: trialEntitlement(),
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: trialEnd
        )
        XCTAssertEqual(notifications.removed, ["truckorig.trial.1001"])
        XCTAssertFalse(controller.shouldShowBanner)
    }

    func testCancelsTheNotificationWhenTheSubscriptionEnds() async {
        notifications.permission = .authorized
        await controller.apply(
            entitlement: trialEntitlement(),
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: trialEnd.addingTimeInterval(-24 * 60 * 60)
        )
        await controller.apply(
            entitlement: nil,
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: trialEnd.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertEqual(notifications.removed, ["truckorig.trial.1001"])
        XCTAssertFalse(controller.isActive)
    }

    func testBannerDismissDoesNotCancelTheNotification() async {
        notifications.permission = .authorized
        controller.now = { self.trialEnd.addingTimeInterval(-24 * 60 * 60) }
        await controller.apply(
            entitlement: trialEntitlement(),
            catalog: PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true),
            now: controller.now()
        )
        XCTAssertTrue(controller.shouldShowBanner)
        let removedBefore = notifications.removed.count
        controller.dismissBanner()
        XCTAssertFalse(controller.shouldShowBanner)
        XCTAssertEqual(notifications.removed.count, removedBefore)
        XCTAssertEqual(notifications.added.count, 1)
    }

    func testFirstRunIsShownOnce() async {
        await controller.apply(
            entitlement: nil,
            catalog: PremiumCatalog(displayPrice: nil, includesFreeMonth: true),
            now: Date()
        )
        XCTAssertTrue(controller.shouldShowFirstRun)
        controller.declineFirstRun()
        XCTAssertFalse(controller.shouldShowFirstRun)
    }

    func testCalendarTriggerDoesNotRepeat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 25
        components.hour = 0
        components.minute = 0
        let trigger = TrialNotificationTrigger.calendar(matching: components)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.day, 25)
        XCTAssertEqual(trigger.dateComponents.month, 2)
    }

    private func trialEntitlement() -> PremiumEntitlement {
        PremiumEntitlement(
            isActive: true,
            purchaseID: "1001",
            facts: SubscriptionPeriodFacts(
                isEntitled: true,
                introductoryFreeTrial: true,
                transactionExpiration: trialEnd,
                renewalDate: trialEnd
            ),
            displayPrice: "$2.99"
        )
    }
}

@MainActor
final class FakeTrialNotifications: TrialNotificationCenter {
    var permission: TrialNotificationPermission = .notDetermined
    var grant = true
    var authorizationRequests = 0
    var added: [(id: String, body: String, components: DateComponents, repeats: Bool)] = []
    var removed: [String] = []

    func authorization() async -> TrialNotificationPermission { permission }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        permission = grant ? .authorized : .denied
        return grant
    }

    func add(
        id: String,
        title: String,
        body: String,
        actionTitle: String,
        components: DateComponents
    ) async throws {
        let trigger = TrialNotificationTrigger.calendar(matching: components)
        added.append((id, body, components, trigger.repeats))
    }

    func remove(identifiers: [String]) {
        removed.append(contentsOf: identifiers)
    }
}

@MainActor
final class FakePremiumGateway: PremiumGateway {
    func loadCatalog() async throws -> PremiumCatalog {
        PremiumCatalog(displayPrice: "$2.99", includesFreeMonth: true)
    }

    func currentEntitlement() async throws -> PremiumEntitlement? { nil }

    func purchase() async throws -> PremiumPurchaseOutcome { .cancelled }

    func restore() async throws {}

    func showManageSubscriptions() async {}

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
