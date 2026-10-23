import XCTest
@testable import TruckoRigDomain

final class MapLogicTests: XCTestCase {

    private let now: Int64 = 1_774_800_000_000

    func testReportsFromLoadsBuildsLaneWithinWeek() {
        let load = sample(
            pointA: "Seattle, WA",
            pointB: "Portland, OR",
            rate: 1200,
            miles: 400,
            parsedAt: now - 2 * 86_400_000
        )
        let reports = CrowdMapAggregator.reportsFromLoads([load], nowMillis: now)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].fromState, "WA")
        XCTAssertEqual(reports[0].toState, "OR")
        XCTAssertEqual(reports[0].rpm, MapMoney.fromDollars(3))
        XCTAssertEqual(reports[0].source, .me)
        XCTAssertEqual(reports[0].id, "anon:0")
        XCTAssertFalse(reports[0].id.contains("SECRET"))
        XCTAssertFalse(reports[0].id.contains("T-"))
    }

    func testReportsFromLoadsSkipsOlderThanWeek() {
        let load = sample(
            pointA: "Dallas, TX",
            pointB: "Austin, TX",
            rate: 800,
            miles: 200,
            parsedAt: now - 10 * 86_400_000
        )
        XCTAssertTrue(CrowdMapAggregator.reportsFromLoads([load], nowMillis: now).isEmpty)
    }

    func testFilterMeOnlyDropsNetwork() {
        let reports = [
            CrowdRateReport(
                id: "m", fromState: "WA", toState: "OR",
                rpm: MapMoney.fromDollars(2.5), rate: MapMoney.fromDollars(1000),
                miles: 400, reportedAtMillis: now, source: .me
            ),
            CrowdRateReport(
                id: "n", fromState: "TX", toState: "OK",
                rpm: MapMoney.fromDollars(2.2), rate: MapMoney.fromDollars(900),
                miles: 400, reportedAtMillis: now, source: .network
            ),
        ]
        let mine = CrowdMapAggregator.filterMeOnly(reports)
        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine[0].source, .me)
    }

    func testStateSummaryListsRecentOutbound() {
        let reports = [
            CrowdRateReport(
                id: "1", fromState: "WA", toState: "OR",
                rpm: MapMoney.fromDollars(2.9), rate: MapMoney.fromDollars(1160),
                miles: 400, reportedAtMillis: now - 3 * 3_600_000, source: .me
            ),
            CrowdRateReport(
                id: "2", fromState: "WA", toState: "CA",
                rpm: MapMoney.fromDollars(2.5), rate: MapMoney.fromDollars(1250),
                miles: 500, reportedAtMillis: now - 2 * 86_400_000, source: .me
            ),
            CrowdRateReport(
                id: "3", fromState: "OR", toState: "WA",
                rpm: MapMoney.fromDollars(3), rate: MapMoney.fromDollars(900),
                miles: 300, reportedAtMillis: now, source: .me
            ),
        ]
        let summary = CrowdMapAggregator.stateSummary(reports, stateCode: "WA")
        XCTAssertEqual(summary.outboundTrips, 2)
        XCTAssertEqual(summary.recent.count, 2)
        XCTAssertEqual(summary.recent[0].toState, "OR")
        XCTAssertTrue(summary.avgOutboundRpm.isPositive)
    }

    func testHeatmapMarksOutboundState() {
        let reports = [
            CrowdRateReport(
                id: "1", fromState: "WA", toState: "OR",
                rpm: MapMoney.fromDollars(3), rate: MapMoney.fromDollars(1200),
                miles: 400, reportedAtMillis: now, source: .me
            ),
        ]
        let metrics = CrowdMapAggregator.heatmapFromOutbound(reports)
        let washington = metrics.first { $0.code == "WA" }
        XCTAssertEqual(washington?.trips, 1)
        XCTAssertEqual(washington?.revenuePerMile ?? 0, 3, accuracy: 0.01)
        XCTAssertNotEqual(washington?.rating, .noData)
        let oregon = metrics.first { $0.code == "OR" }
        XCTAssertEqual(oregon?.trips, 0)
        XCTAssertEqual(oregon?.rating, .noData)
    }

    func testReportsFromLoadsKeepsMonthWindow() {
        let load = sample(
            pointA: "Dallas, TX",
            pointB: "Austin, TX",
            rate: 800,
            miles: 200,
            parsedAt: now - 20 * 86_400_000
        )
        XCTAssertEqual(
            CrowdMapAggregator.reportsFromLoads(
                [load], nowMillis: now, windowMs: MapPeriod.month.windowMs
            ).count,
            1
        )
        XCTAssertTrue(
            CrowdMapAggregator.reportsFromLoads(
                [load], nowMillis: now, windowMs: MapPeriod.week.windowMs
            ).isEmpty
        )
    }

    func testReportsFromLoadsYearIncludesOlderTrips() {
        let load = sample(
            pointA: "Miami, FL",
            pointB: "Orlando, FL",
            rate: 900,
            miles: 250,
            parsedAt: now - 200 * 86_400_000
        )
        XCTAssertEqual(
            CrowdMapAggregator.reportsFromLoads(
                [load], nowMillis: now, windowMs: MapPeriod.year.windowMs
            ).count,
            1
        )
        XCTAssertTrue(
            CrowdMapAggregator.reportsFromLoads(
                [load], nowMillis: now, windowMs: MapPeriod.month.windowMs
            ).isEmpty
        )
    }

    func testReportsFromLoadsCopiesEquipmentType() {
        let load = sample(
            pointA: "Seattle, WA",
            pointB: "Portland, OR",
            rate: 1200,
            miles: 400,
            parsedAt: now - 86_400_000,
            equipmentType: "REEFER"
        )
        let reports = CrowdMapAggregator.reportsFromLoads([load], nowMillis: now)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].equipmentType, "REEFER")
        let sample = CrowdMapAggregator.toAnonymizedSample(reports[0], week: 31, year: 2026)
        XCTAssertEqual(sample.fromState, "WA")
        XCTAssertEqual(sample.equipmentType, "REEFER")
        XCTAssertEqual(sample.rpm, 3, accuracy: 0.01)
        XCTAssertEqual(sample.region, "WA-OR")
    }

    func testHeatmapAggregatesMixedEquipmentInState() {
        let reports = [
            CrowdRateReport(
                id: "a", fromState: "WA", toState: "OR",
                rpm: MapMoney.fromDollars(2), rate: MapMoney.fromDollars(800),
                miles: 400, reportedAtMillis: now, source: .me, equipmentType: "DRY_VAN"
            ),
            CrowdRateReport(
                id: "b", fromState: "WA", toState: "OR",
                rpm: MapMoney.fromDollars(4), rate: MapMoney.fromDollars(1600),
                miles: 400, reportedAtMillis: now, source: .me, equipmentType: "REEFER"
            ),
        ]
        let metrics = CrowdMapAggregator.heatmapFromOutbound(reports)
        let washington = metrics.first { $0.code == "WA" }
        XCTAssertEqual(washington?.trips, 2)
        XCTAssertEqual(washington?.revenuePerMile ?? 0, 3, accuracy: 0.01)
        XCTAssertNotEqual(washington?.rating, .noData)
    }

    func testPeriodSliceDropsWeekButKeepsMonthFromYearCache() {
        let recent = sample(
            pointA: "Seattle, WA", pointB: "Portland, OR",
            rate: 400, miles: 100, parsedAt: now - 2 * 86_400_000
        )
        let older = sample(
            pointA: "Dallas, TX", pointB: "Austin, TX",
            rate: 800, miles: 200, parsedAt: now - 20 * 86_400_000
        )
        let cached = MapSession.cachedReports(loads: [recent, older], nowMillis: now)
        XCTAssertEqual(cached.count, 2)
        let week = MapSession.apply(reports: cached, selectedCode: "", period: .week, nowMillis: now)
        XCTAssertEqual(week.tripCount, 1)
        XCTAssertEqual(week.topLanes.map(\.fromState), ["WA"])
        let month = MapSession.apply(reports: cached, selectedCode: "TX", period: .month, nowMillis: now)
        XCTAssertEqual(month.tripCount, 2)
        XCTAssertEqual(month.stateSummary?.outboundTrips, 1)
        XCTAssertTrue(month.topLanes.isEmpty == false)
        XCTAssertNil(week.stateSummary)
    }

    func testTopLanesLimitAndChipCodes() {
        var reports: [CrowdRateReport] = []
        let lanes = [("WA", "OR"), ("TX", "OK"), ("FL", "GA"), ("NY", "NJ"), ("CA", "NV"), ("IL", "IN"), ("OH", "PA"), ("GA", "FL"), ("NC", "SC")]
        for (index, lane) in lanes.enumerated() {
            reports.append(
                CrowdRateReport(
                    id: "\(index)", fromState: lane.0, toState: lane.1,
                    rpm: MapMoney.fromDollars(2), rate: MapMoney.fromDollars(200),
                    miles: 100, reportedAtMillis: now - Int64(index), source: .me
                )
            )
        }
        XCTAssertEqual(CrowdMapAggregator.topLanes(reports).count, 8)
        let metrics = CrowdMapAggregator.heatmapFromOutbound(reports)
        XCTAssertEqual(CrowdMapAggregator.chipCodes(metrics).count, 6)
        XCTAssertEqual(Set(CrowdMapAggregator.chipCodes(metrics)).count, 6)
    }

    func testAgeBuckets() {
        XCTAssertEqual(CrowdAge.classify(ageMs: 30_000), .minutes(1))
        XCTAssertEqual(CrowdAge.classify(ageMs: 5 * 60_000), .minutes(5))
        XCTAssertEqual(CrowdAge.classify(ageMs: 3 * 3_600_000), .hours(3))
        XCTAssertEqual(CrowdAge.classify(ageMs: 3 * 86_400_000), .days(3))
    }

    func testBlankSelectionOpensOnKentucky() {
        XCTAssertEqual(MapSelection.resolved(nil), "KY")
        XCTAssertEqual(MapSelection.resolved("  "), "KY")
        XCTAssertEqual(MapSelection.resolved("TX"), "TX")
    }

    func testEmptyLoadsAreAllNoData() {
        let metrics = MapStateMetrics.computeFromLoads([])
        XCTAssertEqual(metrics.count, USStateCodes.all.count)
        XCTAssertTrue(metrics.allSatisfy { $0.trips == 0 && $0.rating == .noData })
        XCTAssertTrue(metrics.allSatisfy { $0.revenue == 0 && $0.revenuePerMile == 0 })
    }

    func testSingleLoadMarksDestinationState() {
        let load = sample(
            pointA: "Hopewell Junction, NY",
            pointB: "Garner, NC",
            rate: 2500,
            miles: 1000,
            parsedAt: 1
        )
        let metrics = MapStateMetrics.computeFromLoads([load])
        let carolina = metrics.first { $0.code == "NC" }
        XCTAssertEqual(carolina?.trips, 1)
        XCTAssertEqual(carolina?.revenue ?? 0, 2500, accuracy: 0.01)
        XCTAssertEqual(carolina?.revenuePerMile ?? 0, 2.5, accuracy: 0.01)
        XCTAssertEqual(metrics.first { $0.code == "NY" }?.trips, 0)
    }

    func testStateOutlinesAndPaint() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"name":"Washington"},"geometry":{"type":"Polygon","coordinates":[[[-124.0,49.0],[-117.0,49.0],[-117.0,45.0],[-124.0,45.0],[-124.0,49.0]]]}},
          {"type":"Feature","properties":{"name":"Alaska"},"geometry":{"type":"MultiPolygon","coordinates":[[[[-150.0,70.0],[-140.0,70.0],[-140.0,60.0],[-150.0,60.0],[-150.0,70.0]]],[[[-160.0,55.0],[-155.0,55.0],[-155.0,50.0],[-160.0,50.0],[-160.0,55.0]]]]}}
        ]}
        """.data(using: .utf8)!
        let rings = StateOutlineParser.rings(from: json)
        XCTAssertEqual(rings.filter { $0.stateCode == "WA" }.count, 1)
        XCTAssertEqual(rings.filter { $0.stateCode == "AK" }.count, 2)
        XCTAssertEqual(rings.first { $0.stateCode == "WA" }?.outer.first?.latitude, 49)
        XCTAssertEqual(rings.first { $0.stateCode == "WA" }?.outer.first?.longitude, -124)

        let metric = USStateMetric(
            code: "WA", revenue: 1200, trips: 1, level: .high,
            revenuePerMile: 3, avgMilesPerTrip: 400, rating: .good
        )
        let painted = StateHeatmapPainter.paint(rings: rings, metrics: [metric], selectedCode: "WA")
        let selected = painted.first { $0.stateCode == "WA" }
        XCTAssertEqual(selected?.fillHex, StateOutlineStyle.good)
        XCTAssertEqual(selected?.strokeHex, StateOutlineStyle.selected)
        XCTAssertEqual(selected?.strokeWidth, StateOutlineStyle.strokeSelected)
        XCTAssertEqual(selected?.zIndex, 10)
        let alaska = painted.first { $0.stateCode == "AK" }
        XCTAssertEqual(alaska?.fillHex, StateOutlineStyle.noData)
        XCTAssertEqual(alaska?.strokeWidth, StateOutlineStyle.strokeNormal)
    }

    func testMapsKeySanitizer() throws {
        XCTAssertFalse(MapsAPIKey.isConfigured(nil))
        XCTAssertFalse(MapsAPIKey.isConfigured("  "))
        XCTAssertFalse(MapsAPIKey.isConfigured("$(GOOGLE_MAPS_API_KEY)"))
        XCTAssertFalse(MapsAPIKey.isConfigured("YOUR_API_KEY"))
        XCTAssertTrue(MapsAPIKey.isConfigured("test-key-not-real"))

        let example = try String(contentsOfFile: "Config/Secrets.example.xcconfig", encoding: .utf8)
        XCTAssertFalse(example.contains("AIza"))
        XCTAssertTrue(example.contains("GOOGLE_MAPS_API_KEY"))
        let ignore = try String(contentsOfFile: ".gitignore", encoding: .utf8)
        XCTAssertTrue(ignore.contains("Config/Secrets.xcconfig"))
    }

    private func sample(
        pointA: String,
        pointB: String,
        rate: Double,
        miles: Double,
        parsedAt: Int64,
        equipmentType: String? = nil
    ) -> MapLoadInput {
        MapLoadInput(
            pointA: pointA,
            pointB: pointB,
            totalRateDollars: rate,
            totalMiles: miles,
            parsedAtMillis: parsedAt,
            updatedAtMillis: parsedAt,
            filedOnISO: "2026-07-28",
            equipmentType: equipmentType
        )
    }
}
