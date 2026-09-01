import Foundation
import SwiftData

extension Load {

    var sortedStops: [Stop] {
        (stops ?? []).sorted { $0.stopNumber < $1.stopNumber }
    }

    var pickups: [Stop] { sortedStops.filter { $0.type == .pickup } }
    var deliveries: [Stop] { sortedStops.filter { $0.type == .delivery } }

    var penaltiesTotal: Double {
        (penalties ?? []).reduce(0) { $0 + $1.amount }
    }

    var route: String {
        let from = pointA ?? ""
        let to = pointB ?? ""
        guard !from.isEmpty, !to.isEmpty else { return from.isEmpty ? to : from }
        return "\(from) → \(to)"
    }

    var isActiveDispute: Bool { isDispute && !disputeCompleted }

    var ratePerMile: Double {
        RPMCalculator.ratePerMile(rate: totalRate, miles: totalMiles)
    }

    /// Projection consumed by the pure calculators.
    var summary: LoadSummary {
        LoadSummary(
            id: id,
            tripId: tripId,
            totalRate: totalRate,
            totalMiles: totalMiles,
            firstPickupAt: firstPickupAt,
            lastDeliveryAt: lastDeliveryAt,
            actualFinishAt: actualFinishDate,
            storedDurationDays: durationDays,
            penaltiesTotal: penaltiesTotal,
            isDispute: isDispute,
            disputeCompleted: disputeCompleted,
            originState: pickups.first?.state ?? "",
            destinationState: deliveries.last?.state ?? ""
        )
    }

    /// Date the load is considered finished for the journal: the driver's override, the last
    /// delivery, or the load date.
    var effectiveFinishDate: Date {
        actualFinishDate ?? lastDeliveryAt ?? date
    }

    /// Recomputes every cached field from the current stops.
    ///
    /// Call after any edit to stops or the finish override; the journal, goal and analytics all
    /// read these caches instead of walking relationships.
    func refreshDerivedFields(week: TruckingWeek = TruckingWeek()) {
        let pickups = self.pickups
        let deliveries = self.deliveries

        pointA = pickups.first?.cityState ?? pointA
        pointB = deliveries.last?.cityState ?? pointB
        puCount = pickups.count
        delCount = deliveries.count
        stopCount = sortedStops.count
        firstPickupAt = pickups.compactMap(\.scheduledTime).min()
        lastDeliveryAt = deliveries.compactMap(\.scheduledTime).max()

        if let firstPickupAt { date = firstPickupAt }
        durationDays = LoadYieldCalculator.activeDurationDays(of: summary)

        // File the load in the week it settles: the pickup week, unless delivery slipped into a
        // later week (Saturday pickup, Sunday delivery).
        let pickupWeek = week.week(for: firstPickupAt ?? date)
        let finishWeek = week.week(for: effectiveFinishDate)
        let reportingWeek = max(pickupWeek, finishWeek)
        weekNumber = reportingWeek.weekNumber
        year = reportingWeek.year
    }

    func touch(now: Date = Date()) {
        updatedAt = now
    }
}
