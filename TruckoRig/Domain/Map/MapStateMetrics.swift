import Foundation

/// Destination-state heatmap. Android keeps this next to the live origin-state map.
/// The screen itself colors origin states; this function is the other pure metric.
public enum MapStateMetrics {
    public static func computeFromLoads(_ loads: [MapLoadInput]) -> [USStateMetric] {
        struct Row {
            var state: String
            var rate: MapMoney
            var miles: Double
        }
        let rows: [Row] = loads.compactMap { load in
            guard !load.pointB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  load.drivenMiles > 0,
                  let state = CrowdMapAggregator.extractState(from: load.pointB),
                  USStateCodes.known.contains(state)
            else { return nil }
            return Row(state: state, rate: MapMoney.fromDollars(load.totalRateDollars), miles: load.drivenMiles)
        }
        struct Agg {
            var revenue: Double
            var trips: Int
            var miles: Double
            var rpm: Double { miles > 0 ? revenue / miles : 0 }
        }
        let grouped = Dictionary(grouping: rows, by: \.state)
        let byState: [String: Agg] = grouped.mapValues { list in
            let revenue = sumMoney(list.map(\.rate))
            let miles = list.reduce(0) { $0 + $1.miles }
            return Agg(revenue: revenue.dollars, trips: list.count, miles: miles)
        }
        let ranked = byState
            .filter { $0.value.rpm > 0 }
            .sorted { $0.value.rpm > $1.value.rpm }
        let count = ranked.count
        let goodCount = count > 0 ? max(1, Int(Double(count) * 0.33)) : 0
        let badCount = count > 1 ? max(1, Int(Double(count) * 0.33)) : 0
        var rpmRank: [String: Int] = [:]
        for (index, entry) in ranked.enumerated() {
            rpmRank[entry.key] = index
        }
        let metrics = USStateCodes.all.map { code -> USStateMetric in
            let agg = byState[code] ?? Agg(revenue: 0, trips: 0, miles: 0)
            let rank = rpmRank[code] ?? count
            let level: USHeatLevel = {
                if agg.trips == 0 { return .low }
                if rank < goodCount { return .high }
                if rank < count - badCount { return .medium }
                return .low
            }()
            let rating: StateRating = {
                if agg.trips == 0 { return .noData }
                if rank < goodCount { return .good }
                if rank >= count - badCount && badCount > 0 { return .bad }
                return .neutral
            }()
            return USStateMetric(
                code: code,
                revenue: agg.revenue,
                trips: agg.trips,
                level: level,
                revenuePerMile: agg.rpm,
                avgMilesPerTrip: agg.trips > 0 ? agg.miles / Double(agg.trips) : 0,
                rating: rating
            )
        }
        return metrics.sorted { $0.revenue > $1.revenue }
    }
}
