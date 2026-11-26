import SwiftUI
import UIKit
import WidgetKit
import XCTest
@testable import TruckoRig

/// Renders the production goal screen, home card, and widget for a week at 130% of the goal.
///
/// The simulator test writes PNGs into the app container. The macOS workflow copies
/// `Documents/goal-percent-shots` and uploads them. These are the live SwiftUI views, not drawings.
@MainActor
final class GoalPercentScreenshotTests: XCTestCase {

    private let shotDirectoryName = "goal-percent-shots"

    override func tearDown() {
        AppLocale.apply(.system)
        super.tearDown()
    }

    func testCaptureGoalScreenAndWidgetAtOneHundredThirtyPercent() async throws {
        let harness = try await makeHarness()
        let progress = harness.progress
        XCTAssertEqual(progress.currentGross, 13_000, accuracy: 0.01)
        XCTAssertEqual(progress.targetAmount, 10_000, accuracy: 0.01)
        XCTAssertEqual(progress.currentGross / progress.targetAmount, 1.3, accuracy: 0.001)
        // The displayed text follows production. A cap still in place reports 100 here.
        XCTAssertGreaterThanOrEqual(progress.progressPercent, 100)

        let locale = Locale(identifier: "ru")
        let goal = NavigationStack {
            WeeklyGoalView()
        }
        .environment(harness.appState)
        .environment(\.locale, locale)
        .environment(\.cabinReduceMotion, true)

        try await capture(goal, size: CGSize(width: 393, height: 852), name: "goal-screen")

        let snapshot = try widgetSnapshot(progress: progress, harness: harness, locale: locale)
        try await capture(
            WeeklyGoalWidgetView(snapshot: snapshot, familyOverride: .systemSmall)
                .environment(\.locale, locale),
            size: CGSize(width: 158, height: 158),
            name: "widget-small"
        )
        try await capture(
            WeeklyGoalWidgetView(snapshot: snapshot, familyOverride: .systemMedium)
                .environment(\.locale, locale),
            size: CGSize(width: 338, height: 158),
            name: "widget-medium"
        )
        try await capture(
            WeeklyGoalWidgetView(snapshot: snapshot, familyOverride: .accessoryCircular)
                .environment(\.locale, locale),
            size: CGSize(width: 76, height: 76),
            name: "widget-circular"
        )
        try await capture(
            homeCard(progress: progress, harness: harness),
            size: CGSize(width: 360, height: 280),
            name: "home-card"
        )
    }

    private func makeHarness() async throws -> Harness {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database)
        try repository.create(
            LoadDraft(tripId: "OVER-130", date: Date(), totalRate: 13_000, totalMiles: 800)
        )
        let scope = AccountScope.user("goalshots")
        let defaults = try isolatedDefaults("com.truckorig.goalshots")
        let settings = AppSettings(scope: scope, defaults: defaults, widgetDefaults: defaults)
        settings.language = .russian
        settings.weeklyGoal = 10_000
        let persistence = PersistenceController(database: database, scope: scope)
        let premiumDefaults = try isolatedDefaults("com.truckorig.goalshots.premium")
        let premium = PremiumController(inactiveStore: PremiumLocalStore(defaults: premiumDefaults))
        let appState = AppState(
            persistence: persistence,
            settings: settings,
            premium: premium,
            loadsCatalog: true
        )
        let facts = SubscriptionPeriodFacts(
            isEntitled: true,
            introductoryFreeTrial: false,
            transactionExpiration: nil,
            renewalDate: nil
        )
        let entitlement = PremiumEntitlement(
            isActive: true,
            purchaseID: "goal-shot",
            facts: facts,
            displayPrice: nil
        )
        let catalog = PremiumCatalog(displayPrice: nil, includesFreeMonth: false)
        await premium.apply(entitlement: entitlement, catalog: catalog, now: Date())
        XCTAssertTrue(premium.isActive)
        XCTAssertTrue(premium.didRefresh)
        XCTAssertEqual(appState.catalog.loads.count, 1)
        let week = settings.truckingWeek
        let progress = WeeklyGoalViewModel().progress(
            loads: appState.catalog.loads,
            target: settings.weeklyGoal,
            calendar: week,
            locale: Locale(identifier: "ru")
        )
        return Harness(appState: appState, settings: settings, progress: progress)
    }

    private func widgetSnapshot(
        progress: WeeklyGoalProgress,
        harness: Harness,
        locale: Locale
    ) throws -> WidgetGoalSnapshot {
        let week = harness.settings.truckingWeek
        let ref = week.currentWeek()
        let start = try XCTUnwrap(week.startDate(of: ref))
        let end = try XCTUnwrap(week.endDate(of: ref))
        return WidgetSnapshotBuilder.make(
            progress: progress,
            weekStart: start,
            weekEnd: end,
            calendar: week.calendar,
            locale: locale
        )
    }

    private func homeCard(progress: WeeklyGoalProgress, harness: Harness) -> some View {
        let week = harness.settings.truckingWeek
        let ref = week.currentWeek()
        let locale = Locale(identifier: "ru")
        let caption: String = {
            guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else {
                return progress.weekLabel
            }
            return SplitWeekRange.homeCaption(start: start, end: end, calendar: week.calendar, locale: locale)
        }()
        let miles = progress.totalMiles
        let rpm = miles > 0 ? USMoneyFormat.rpmPerMile(progress.currentGross / miles) : "—"
        return HomeWeekHeroCard(
            weekNumber: ref.weekNumber,
            rangeCaption: caption,
            gross: progress.currentGross,
            goal: progress.targetAmount,
            percent: progress.progressPercent,
            rpmText: rpm,
            milesText: USMoneyFormat.number(miles),
            loadCount: progress.loadsCount,
            dayLabels: dayLabels(week: week, ref: ref, locale: locale),
            elapsedDays: week.daysElapsed()
        )
        .environment(\.locale, locale)
    }

    private func dayLabels(week: TruckingWeek, ref: WeekRef, locale: Locale) -> [String] {
        guard let start = week.startDate(of: ref) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = week.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DateUtils.string(day, format: "EEEEE", locale: locale, calendar: week.calendar)
        }
    }

    private func capture<V: View>(_ view: V, size: CGSize, name: String) async throws {
        let host = UIHostingController(rootView: view.frame(width: size.width, height: size.height).ignoresSafeArea())
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = .light
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.overrideUserInterfaceStyle = .light
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        UIView.setAnimationsEnabled(false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 700_000_000)
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true

        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 1_000, "\(name) rendered an empty image")
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(shotDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).png")
        try data.write(to: url, options: .atomic)
        print("goal-percent-shot \(url.path)")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func isolatedDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

@MainActor
private struct Harness {
    let appState: AppState
    let settings: AppSettings
    let progress: WeeklyGoalProgress
}
