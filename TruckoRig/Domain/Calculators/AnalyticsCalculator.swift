import Foundation

/// Gross and miles for one reporting week.
public struct WeeklyPoint: Identifiable, Equatable, Sendable {
    public let week: WeekRef
    public let label: String
    public let gross: Double
    public let miles: Double
    public let loadCount: Int

    public var id: WeekRef { week }
    public var ratePerMile: Double { RPMCalculator.ratePerMile(rate: gross, miles: miles) }
}

/// What a state is worth to the driver.
public struct StateRevenue: Identifiable, Equatable, Sendable {
    public let state: String
    public let gross: Double
    public let miles: Double
    public let loadCount: Int

    public var id: String { state }
    public var ratePerMile: Double { RPMCalculator.ratePerMile(rate: gross, miles: miles) }
}

/// A lane the driver runs repeatedly.
public struct RouteStat: Identifiable, Equatable, Sendable {
    public let origin: String
    public let destination: String
    public let gross: Double
    public let miles: Double
    public let loadCount: Int

    public var id: String { "\(origin)→\(destination)" }
    public var label: String { "\(origin) → \(destination)" }
    public var averageGross: Double { loadCount > 0 ? gross / Double(loadCount) : 0 }
    public var ratePerMile: Double { RPMCalculator.ratePerMile(rate: gross, miles: miles) }
}

/// Aggregations behind the analytics screen and the state heatmap.
public enum AnalyticsCalculator {

    /// Gross per week for the last `weeks` reporting weeks, oldest first.
    ///
    /// Weeks with no loads are still emitted so a chart shows the gap rather than closing it up.
    public static func weeklySeries(
        loads: [LoadSummary],
        weeks: Int,
        calendar: TruckingWeek = TruckingWeek(),
        locale: Locale = .current,
        now: Date = Date()
    ) -> [WeeklyPoint] {
        guard weeks > 0 else { return [] }
        let formatter = WeekLabelFormatter(week: calendar, locale: locale)
        let current = calendar.currentWeek(now: now)

        let grouped = Dictionary(grouping: loads) { load -> WeekRef in
            calendar.week(for: load.firstPickupAt ?? load.lastDeliveryAt ?? now)
        }

        return (0..<weeks).reversed().map { offset in
            let ref = calendar.shift(current, by: -offset)
            let weekLoads = grouped[ref] ?? []
            let totals = LoadTotals.of(weekLoads)
            return WeeklyPoint(
                week: ref,
                label: formatter.label(for: ref),
                gross: GoalMoneyMath.roundMoney(totals.totalRate),
                miles: totals.totalMiles,
                loadCount: totals.loadCount
            )
        }
    }

    /// Gross by state, highest first.
    ///
    /// A load is credited to where it was delivered — that is the state the driver was paid to
    /// reach — falling back to the origin when the delivery state is unknown.
    public static func stateRevenue(loads: [LoadSummary]) -> [StateRevenue] {
        var buckets: [String: (gross: Double, miles: Double, count: Int)] = [:]
        for load in loads {
            let state = load.destinationState.isEmpty ? load.originState : load.destinationState
            guard !state.isEmpty else { continue }
            var bucket = buckets[state] ?? (0, 0, 0)
            bucket.gross += load.totalRate
            bucket.miles += load.totalMiles
            bucket.count += 1
            buckets[state] = bucket
        }
        return buckets
            .map { StateRevenue(state: $0.key, gross: GoalMoneyMath.roundMoney($0.value.gross), miles: $0.value.miles, loadCount: $0.value.count) }
            .sorted { $0.gross > $1.gross }
    }

    /// Most-run lanes, highest gross first.
    public static func topRoutes(loads: [LoadSummary], limit: Int = 10) -> [RouteStat] {
        var buckets: [String: (origin: String, destination: String, gross: Double, miles: Double, count: Int)] = [:]
        for load in loads {
            let origin = load.originState
            let destination = load.destinationState
            guard !origin.isEmpty || !destination.isEmpty else { continue }
            let key = "\(origin)→\(destination)"
            var bucket = buckets[key] ?? (origin, destination, 0, 0, 0)
            bucket.gross += load.totalRate
            bucket.miles += load.totalMiles
            bucket.count += 1
            buckets[key] = bucket
        }
        return buckets.values
            .map {
                RouteStat(
                    origin: $0.origin,
                    destination: $0.destination,
                    gross: GoalMoneyMath.roundMoney($0.gross),
                    miles: $0.miles,
                    loadCount: $0.count
                )
            }
            .sorted { ($0.gross, $0.loadCount) > ($1.gross, $1.loadCount) }
            .prefix(limit)
            .map { $0 }
    }

    /// Miles per gallon between consecutive full fill-ups.
    ///
    /// Needs odometer readings: without them the gallons alone say nothing about distance. Returns
    /// zero rather than a fabricated figure when there is not enough data.
    public static func milesPerGallon(odometers: [(odometer: Int, gallons: Double)]) -> Double {
        let ordered = odometers.filter { $0.odometer > 0 }.sorted { $0.odometer < $1.odometer }
        guard ordered.count >= 2 else { return 0 }
        let distance = Double(ordered[ordered.count - 1].odometer - ordered[0].odometer)
        // The first fill-up's gallons filled the tank used before tracking began.
        let gallons = ordered.dropFirst().reduce(0) { $0 + $1.gallons }
        guard distance > 0, gallons > 0 else { return 0 }
        return (distance / gallons * 10).rounded() / 10
    }
}
