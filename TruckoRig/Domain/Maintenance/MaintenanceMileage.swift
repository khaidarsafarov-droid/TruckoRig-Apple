import Foundation

/// ТО mileage from journal loads. Port of `MaintenanceMileageUseCase` and
/// `MaintenanceProgressCalculator`.
///
/// Formulas (all whole-mile arithmetic):
/// - targetOdometer = baseOdometer + targetInterval
/// - milesSinceService = Σ load.miles where endDate >= serviceDate and endDate <= end of the
///   current trucking week
/// - currentOdometer = baseOdometer + milesSinceService
/// - remainingMiles = targetOdometer - currentOdometer
///
/// The trip end date is actualFinishDate, then last delivery, then the filing date. A same-day
/// finish counts. Pickup date is not the cutoff.
public enum MaintenanceMileage {

    /// Ignore single-load outliers (corrupt / non-mile values).
    public static let maxPlausibleLoadMiles: Int64 = 15_000

    public struct LoadInput: Equatable, Sendable {
        public var tripId: String
        public var id: String
        public var miles: Double
        public var date: String
        public var actualFinishDate: String?
        public var lastDeliveryAt: Date?

        public init(
            tripId: String,
            id: String,
            miles: Double,
            date: String,
            actualFinishDate: String? = nil,
            lastDeliveryAt: Date? = nil
        ) {
            self.tripId = tripId
            self.id = id
            self.miles = miles
            self.date = date
            self.actualFinishDate = actualFinishDate
            self.lastDeliveryAt = lastDeliveryAt
        }
    }

    public struct MileageSnapshot: Equatable, Sendable {
        public var targetOdometer: Int64
        public var totalDrivenMiles: Int64
        public var currentOdometer: Int64
        public var remainingMiles: Int64
        public var milesSinceService: Int64
        public var loadCount: Int
        public var isUrgent: Bool
        public var progressFraction: Double
    }

    public static func milesAsLong(_ raw: Double) -> Int64 {
        guard raw.isFinite, raw > 0 else { return 0 }
        return min(Int64(raw.rounded(.toNearestOrAwayFromZero)), maxPlausibleLoadMiles)
    }

    /// Inclusive upper bound: Saturday (or the configured week end) of the trucking week
    /// that contains `today`.
    public static func inclusiveEndDateCap(today: Date, week: TruckingWeek) -> String {
        let ref = week.week(for: today)
        guard let end = week.endDate(of: ref) else { return isoDay(today, calendar: week.calendar) }
        return isoDay(end, calendar: week.calendar)
    }

    /// Trip end date: actualFinishDate → last delivery → filing date.
    public static func resolveEndDate(_ load: LoadInput, calendar: Calendar) -> String? {
        if let finish = load.actualFinishDate?.trimmingCharacters(in: .whitespacesAndNewlines), finish.count >= 10 {
            return String(finish.prefix(10))
        }
        if let delivered = load.lastDeliveryAt {
            return isoDay(delivered, calendar: calendar)
        }
        if load.date.count >= 10 { return String(load.date.prefix(10)) }
        return nil
    }

    public static func calculate(
        baseOdometer: Int64,
        targetInterval: Int64,
        serviceDate: String,
        loads: [LoadInput],
        today: Date,
        week: TruckingWeek
    ) -> MileageSnapshot {
        let service = String(serviceDate.prefix(10))
        let endCap = inclusiveEndDateCap(today: today, week: week)
        var seen = Set<String>()
        var totalDriven: Int64 = 0
        var loadCount = 0

        for load in loads {
            let miles = milesAsLong(load.miles)
            if miles <= 0 { continue }
            guard let endDate = resolveEndDate(load, calendar: week.calendar) else { continue }
            if endDate < service { continue }
            if endDate > endCap { continue }
            let key = load.tripId.isEmpty ? load.id : load.tripId
            if !seen.insert(key).inserted { continue }
            totalDriven += miles
            loadCount += 1
        }

        let safeBase = max(0, baseOdometer)
        let safeInterval = max(0, targetInterval)
        let target = safeBase + safeInterval
        let current = safeBase + totalDriven
        let remaining = target - current
        let urgent = safeInterval > 0 && remaining <= 0
        let fraction: Double
        if safeInterval > 0 {
            fraction = min(1, max(0, Double(totalDriven) / Double(safeInterval)))
        } else {
            fraction = 0
        }
        return MileageSnapshot(
            targetOdometer: target,
            totalDrivenMiles: totalDriven,
            currentOdometer: current,
            remainingMiles: remaining,
            milesSinceService: totalDriven,
            loadCount: loadCount,
            isUrgent: urgent,
            progressFraction: fraction
        )
    }

    public static func progress(
        task: MaintenanceTask,
        loads: [LoadInput],
        today: Date,
        week: TruckingWeek
    ) -> MaintenanceProgress {
        switch task.reminderType {
        case .miles:
            let base = max(0, Int64((task.odometerAtStart ?? 0).rounded(.toNearestOrAwayFromZero)))
            let interval = max(0, Int64((task.intervalMiles ?? 0).rounded(.toNearestOrAwayFromZero)))
            let snap = calculate(
                baseOdometer: base,
                targetInterval: interval,
                serviceDate: task.startDate,
                loads: loads,
                today: today,
                week: week
            )
            return MaintenanceProgress(
                task: task,
                milesDrivenSinceStart: Double(snap.milesSinceService),
                estimatedOdometer: Double(snap.currentOdometer),
                targetOdometer: Double(snap.targetOdometer),
                milesRemaining: Double(max(0, snap.remainingMiles)),
                daysRemaining: nil,
                isDue: snap.isUrgent,
                loadsCounted: snap.loadCount,
                progressFraction: snap.progressFraction
            )
        case .date:
            let due = task.dueDate.flatMap { parseDay(String($0.prefix(10)), calendar: week.calendar) }
            let todayDay = week.calendar.startOfDay(for: today)
            let daysLeft = due.map { Int64(dayDistance(from: todayDay, to: $0, calendar: week.calendar)) }
            let isDue = due.map { todayDay >= $0 } ?? false
            return MaintenanceProgress(
                task: task,
                milesDrivenSinceStart: 0,
                estimatedOdometer: task.odometerAtStart,
                targetOdometer: nil,
                milesRemaining: nil,
                daysRemaining: daysLeft,
                isDue: isDue,
                loadsCounted: 0,
                progressFraction: 0
            )
        }
    }

    /// Legacy path used by callers that already summed the miles.
    /// Same-day finish after the service counts, matching `MaintenanceProgressCalculator`.
    public static func progress(
        task: MaintenanceTask,
        milesDrivenSinceStart: Double,
        today: Date,
        week: TruckingWeek,
        loadsCounted: Int = 0
    ) -> MaintenanceProgress {
        let loads: [LoadInput]
        if milesDrivenSinceStart > 0 && task.reminderType == .miles {
            loads = [
                LoadInput(
                    tripId: "SUM",
                    id: "SUM",
                    miles: milesDrivenSinceStart,
                    date: task.startDate,
                    actualFinishDate: task.startDate
                ),
            ]
        } else {
            loads = []
        }
        var result = progress(task: task, loads: loads, today: today, week: week)
        if loadsCounted > 0 { result.loadsCounted = loadsCounted }
        return result
    }

    public static func shouldNotify(_ progress: MaintenanceProgress) -> Bool {
        if progress.task.isCompleted { return false }
        if progress.task.notifiedAt != nil { return false }
        return progress.isDue
    }

    public static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func parseDay(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    private static func dayDistance(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

public enum MaintenanceVisits {
    public static func group(_ entries: [MaintenanceArchiveEntry]) -> [MaintenanceVisit] {
        let grouped = Dictionary(grouping: entries) { entry in
            VisitKey(date: entry.serviceDate, photoPath: entry.photoPath ?? "", createdAt: entry.createdAt)
        }
        return grouped.map { key, lines in
            let ordered = lines.sorted { $0.id < $1.id }
            return MaintenanceVisit(
                shopName: ordered.first { !$0.serviceName.trimmingCharacters(in: .whitespaces).isEmpty }?.serviceName ?? "",
                serviceDate: key.date,
                photoPath: ordered.first { !($0.photoPath ?? "").isEmpty }?.photoPath,
                createdAt: key.createdAt,
                lines: ordered
            )
        }
        .sorted { lhs, rhs in
            if lhs.serviceDate != rhs.serviceDate { return lhs.serviceDate > rhs.serviceDate }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private struct VisitKey: Hashable {
        var date: String
        var photoPath: String
        var createdAt: Int64
    }
}
