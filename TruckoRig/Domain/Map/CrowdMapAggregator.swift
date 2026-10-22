import Foundation

/// Local map math from the driver's own loads. Port of Android `CrowdMapAggregator` and the
/// pieces of `CrowdRpmMapper` it calls.
///
/// Heatmap buckets are the origin state. A report id is `anon:<index>`, never a trip id.
public enum CrowdMapAggregator {

    public static let weekMs: Int64 = MapPeriod.week.windowMs
    private static let skewMs: Int64 = 3_600_000

    public static func reportsFromLoads(
        _ loads: [MapLoadInput],
        nowMillis: Int64,
        windowMs: Int64 = weekMs
    ) -> [CrowdRateReport] {
        let cutoff = nowMillis - windowMs
        let skew = nowMillis + skewMs
        return loads.enumerated().compactMap { index, load in
            let at = eventTimeMillis(load)
            if at < cutoff || at > skew { return nil }
            guard let from = originState(load), USStateCodes.known.contains(from) else { return nil }
            guard let to = destState(load), USStateCodes.known.contains(to) else { return nil }
            guard let sample = anonymized(load, from: from, to: to) else { return nil }
            let rpmMoney = MapMoney.fromDollars(sample.rpm)
            return CrowdRateReport(
                id: "anon:\(index)",
                fromState: from,
                toState: to,
                rpm: rpmMoney,
                rate: rpmMoney.scaledBy(sample.miles),
                miles: sample.miles,
                reportedAtMillis: at,
                source: .me,
                equipmentType: load.equipmentType
            )
        }
    }

    public static func toAnonymizedSample(
        _ report: CrowdRateReport,
        week: Int,
        year: Int
    ) -> AnonymizedRpmSample {
        AnonymizedRpmSample(
            rpm: report.rpm.dollars,
            miles: report.miles,
            region: regionOf(report.fromState, report.toState),
            weekNumber: week,
            fromState: report.fromState,
            toState: report.toState,
            week: week,
            year: year,
            equipmentType: report.equipmentType
        )
    }

    public static func filterMeOnly(_ reports: [CrowdRateReport]) -> [CrowdRateReport] {
        reports.filter { $0.source == .me }
    }

    public static func heatmapFromOutbound(_ reports: [CrowdRateReport]) -> [USStateMetric] {
        var order: [String] = []
        var lists: [String: [CrowdRateReport]] = [:]
        for report in reports {
            if lists[report.fromState] == nil { order.append(report.fromState) }
            lists[report.fromState, default: []].append(report)
        }
        var byState: [String: StateAgg] = [:]
        for code in order {
            let list = lists[code] ?? []
            let revenue = sumMoney(list.map(\.rate))
            byState[code] = StateAgg(
                revenue: revenue.dollars,
                trips: list.count,
                miles: list.reduce(0) { $0 + $1.miles }
            )
        }
        return rank(byState, tieOrder: order)
    }

    public static func stateSummary(
        _ reports: [CrowdRateReport],
        stateCode: String,
        recentLimit: Int = 12
    ) -> CrowdStateSummary {
        let outbound = reports.filter { $0.fromState == stateCode }
        let miles = outbound.reduce(0) { $0 + $1.miles }
        let revenue = sumMoney(outbound.map(\.rate))
        let avg = miles > 0
            ? MapMoney.fromCents(halfAwayFromZero(Double(revenue.cents) / miles))
            : .zero
        let recent = outbound.sorted { $0.reportedAtMillis > $1.reportedAtMillis }.prefix(recentLimit)
        return CrowdStateSummary(
            stateCode: stateCode,
            outboundTrips: outbound.count,
            avgOutboundRpm: avg,
            totalRevenue: revenue,
            totalMiles: miles,
            recent: Array(recent)
        )
    }

    public static func topLanes(_ reports: [CrowdRateReport], limit: Int = 8) -> [CrowdLaneAggregate] {
        var order: [LaneKey] = []
        var lists: [LaneKey: [CrowdRateReport]] = [:]
        for report in reports {
            let key = LaneKey(from: report.fromState, to: report.toState)
            if lists[key] == nil { order.append(key) }
            lists[key, default: []].append(report)
        }
        let lanes = order.map { key -> CrowdLaneAggregate in
            let list = lists[key] ?? []
            let miles = list.reduce(0) { $0 + $1.miles }
            let revenue = sumMoney(list.map(\.rate))
            let avg = miles > 0
                ? MapMoney.fromCents(halfAwayFromZero(Double(revenue.cents) / miles))
                : .zero
            return CrowdLaneAggregate(
                fromState: key.from,
                toState: key.to,
                tripCount: list.count,
                avgRpm: avg,
                totalRevenue: revenue,
                totalMiles: miles
            )
        }
        return lanes.sorted { $0.tripCount > $1.tripCount }.prefix(limit).map { $0 }
    }

    public static func chipCodes(_ metrics: [USStateMetric], limit: Int = 6) -> [String] {
        Array(metrics.sorted { $0.revenue > $1.revenue }.prefix(limit).map(\.code))
    }

    public static func originState(_ load: MapLoadInput) -> String? {
        twoLetterState(load.pointA)
    }

    public static func destState(_ load: MapLoadInput) -> String? {
        twoLetterState(load.pointB)
    }

    public static func eventTimeMillis(_ load: MapLoadInput) -> Int64 {
        if load.parsedAtMillis > 0 { return load.parsedAtMillis }
        if load.updatedAtMillis > 0 { return load.updatedAtMillis }
        return utcDayMillis(load.filedOnISO) ?? 0
    }

    public static func regionOf(_ fromState: String?, _ toState: String?) -> String? {
        let from = fromState?.count == 2 ? fromState : nil
        let to = toState?.count == 2 ? toState : nil
        switch (from, to) {
        case let (from?, to?) where from == to: return from
        case let (from?, to?): return "\(from)-\(to)"
        case let (from?, nil): return from
        case let (nil, to?): return to
        default: return nil
        }
    }

    /// `"City, ST"` or a trailing 2-letter token. Port of `extractStateFromLocation`.
    public static func extractState(from location: String) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let comma = trimmed.lastIndex(of: ",") {
            let after = trimmed[trimmed.index(after: comma)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if after.count == 2, after.allSatisfy(\.isLetter) {
                return after.uppercased()
            }
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = trailingStateRegex.firstMatch(in: trimmed, range: range),
              let capture = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        let token = String(trimmed[capture])
        guard token.count == 2, token.allSatisfy(\.isLetter) else { return nil }
        return token.uppercased()
    }

    private static let trailingStateRegex = try! NSRegularExpression(pattern: #"\b([A-Za-z]{2})\s*$"#)

    private static func twoLetterState(_ location: String) -> String? {
        guard let code = extractState(from: location) else { return nil }
        guard code.count == 2, code.allSatisfy(\.isLetter) else { return nil }
        return code.uppercased()
    }

    private static func anonymized(
        _ load: MapLoadInput,
        from: String,
        to: String
    ) -> (rpm: Double, miles: Double)? {
        let rate = MapMoney.fromDollars(load.totalRateDollars)
        guard load.totalMiles > 0, rate.isPositive else { return nil }
        let rpm = Double(rate.cents) / 100.0 / load.totalMiles
        return (rpm, load.totalMiles)
    }

    private static func utcDayMillis(_ iso: String) -> Int64? {
        let day = String(iso.prefix(10))
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let dayNumber = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(year: year, month: month, day: dayNumber)
        guard let date = calendar.date(from: components) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private struct StateAgg {
        var revenue: Double
        var trips: Int
        var miles: Double
        var rpm: Double { miles > 0 ? revenue / miles : 0 }
    }

    private struct LaneKey: Hashable {
        var from: String
        var to: String
    }

    private static func rank(_ byState: [String: StateAgg], tieOrder: [String]) -> [USStateMetric] {
        let ranked = tieOrder.compactMap { code -> (key: String, value: StateAgg)? in
            guard let agg = byState[code], agg.rpm > 0 else { return nil }
            return (code, agg)
        }.sorted { lhs, rhs in
            lhs.value.rpm > rhs.value.rpm
        }
        let count = ranked.count
        let goodCount = count > 0 ? max(1, Int(Double(count) * 0.33)) : 0
        let badCount = count > 1 ? max(1, Int(Double(count) * 0.33)) : 0
        var rpmRank: [String: Int] = [:]
        for (index, entry) in ranked.enumerated() {
            rpmRank[entry.key] = index
        }

        let metrics = USStateCodes.all.map { code -> USStateMetric in
            let agg = byState[code] ?? StateAgg(revenue: 0, trips: 0, miles: 0)
            let rank = rpmRank[code] ?? count
            let level: USHeatLevel
            if agg.trips == 0 {
                level = .low
            } else if rank < goodCount {
                level = .high
            } else if rank < count - badCount {
                level = .medium
            } else {
                level = .low
            }
            let rating: StateRating
            if agg.trips == 0 {
                rating = .noData
            } else if rank < goodCount {
                rating = .good
            } else if rank >= count - badCount && badCount > 0 {
                rating = .bad
            } else {
                rating = .neutral
            }
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

/// Year-long cache, then a period slice. Same two steps as `MapViewModel`.
public enum MapSession {
    public static func cachedReports(loads: [MapLoadInput], nowMillis: Int64) -> [CrowdRateReport] {
        CrowdMapAggregator.reportsFromLoads(
            loads,
            nowMillis: nowMillis,
            windowMs: MapPeriod.year.windowMs
        )
    }

    public static func apply(
        reports: [CrowdRateReport],
        selectedCode: String,
        period: MapPeriod,
        nowMillis: Int64
    ) -> MapSnapshot {
        let cutoff = nowMillis - period.windowMs
        let windowed = reports.filter { $0.reportedAtMillis >= cutoff }
        let summary = selectedCode.isEmpty
            ? nil
            : CrowdMapAggregator.stateSummary(windowed, stateCode: selectedCode)
        return MapSnapshot(
            metrics: CrowdMapAggregator.heatmapFromOutbound(windowed),
            selectedCode: selectedCode,
            period: period,
            tripCount: windowed.count,
            stateSummary: summary,
            topLanes: CrowdMapAggregator.topLanes(windowed)
        )
    }
}
