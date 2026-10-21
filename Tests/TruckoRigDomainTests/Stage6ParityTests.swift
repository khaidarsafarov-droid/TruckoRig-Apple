import XCTest
@testable import TruckoRigDomain

final class Stage6ParityTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        return calendar
    }

    func testDecimalInputMatchesAndroidSeparatorRules() {
        XCTAssertEqual(DecimalInput.parse("2,500.50"), 2500.50)
        XCTAssertEqual(DecimalInput.parse("2.500,50"), 2500.50)
        XCTAssertEqual(DecimalInput.parse("25,5"), 25.5)
        XCTAssertEqual(DecimalInput.parse("$2,500"), 2500)
        XCTAssertEqual(DecimalInput.parse("1,234,56"), 1234.56)
        XCTAssertNil(DecimalInput.parse("abc"))
    }

    func testReceiptDates() {
        XCTAssertEqual(ReceiptDateParser.normalize("2026-03-15", defaultYear: 2026), "2026-03-15")
        XCTAssertEqual(ReceiptDateParser.normalize("15.03.2026", defaultYear: 2026), "2026-03-15")
        XCTAssertEqual(ReceiptDateParser.normalize("03/15/2026", defaultYear: 2026), "2026-03-15")
        XCTAssertEqual(ReceiptDateParser.normalize("15/03/2026", defaultYear: 2026), "2026-03-15")
        XCTAssertEqual(ReceiptDateParser.normalize("Jul 15, 2026", defaultYear: 2026), "2026-07-15")
        XCTAssertEqual(ReceiptDateParser.normalize("3/15", defaultYear: 2026), "2026-03-15")
    }

    func testDieselPaidTotalAndSavings() {
        XCTAssertEqual(DieselPurchaseMath.paidTotal(gallons: 500, pricePerGallon: 5.10, discountPricePerGallon: 4.09) ?? -1, 2045, accuracy: 0.001)
        XCTAssertEqual(DieselPurchaseMath.savings(gallons: 500, pricePerGallon: 5.10, discountPricePerGallon: 4.09) ?? -1, 505, accuracy: 0.001)
        XCTAssertEqual(DieselPurchaseMath.savings(gallons: 10, pricePerGallon: 4, discountPricePerGallon: 4.5), 0)
        XCTAssertNil(DieselPurchaseMath.paidTotal(gallons: 0, pricePerGallon: 4, discountPricePerGallon: nil))
    }

    func testDieselFormRejectsDiscountAboveList() {
        XCTAssertEqual(DieselFormValidation.validate(gallonsText: "", priceText: "4", discountText: ""), .gallons)
        XCTAssertEqual(DieselFormValidation.validate(gallonsText: "10", priceText: "", discountText: ""), .price)
        XCTAssertEqual(DieselFormValidation.validate(gallonsText: "10", priceText: "4", discountText: "abc"), .discountInvalid)
        XCTAssertEqual(DieselFormValidation.validate(gallonsText: "10", priceText: "4", discountText: "5"), .discountAbovePrice)
        XCTAssertNil(DieselFormValidation.validate(gallonsText: "10", priceText: "4.10", discountText: "3.99"))
    }

    func testDieselGradeIsNotAGallonCount() {
        let broken = DieselReceiptFields(gallons: 2, pricePerGallon: 4, totalAmount: 400)
        let fixed = DieselReceiptExtractor.reconcile(broken, text: "#2 diesel")
        XCTAssertEqual(fixed.gallons ?? 0, 100, accuracy: 0.001)

        let kept = DieselReceiptExtractor.reconcile(broken, text: "diesel fuel")
        XCTAssertEqual(kept.gallons ?? 0, 2, accuracy: 0.001)
    }

    func testDieselReceiptExtractsPumpFields() {
        let text = """
        Love's
        Dallas, TX
        Diesel
        Gallons 120.5
        Price $4.199 / gal
        Discount price $3.899
        Total Amount $505.98
        Date: 03/15/2026
        """
        let parsed = DieselTextParser.parse(text, defaultYear: 2026)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.gallons ?? 0, 120.5, accuracy: 0.001)
        XCTAssertEqual(parsed?.pricePerGallon ?? 0, 4.199, accuracy: 0.001)
        XCTAssertEqual(parsed?.discountPricePerGallon ?? 0, 3.899, accuracy: 0.001)
        XCTAssertEqual(parsed?.totalAmount ?? 0, 505.98, accuracy: 0.001)
        XCTAssertEqual(parsed?.date, "2026-03-15")
        XCTAssertTrue(parsed?.location?.contains("Love's") == true)
        XCTAssertTrue(parsed?.location?.contains("Dallas, TX") == true)
        XCTAssertTrue(DieselTextParser.looksLikeDiesel(text))
        XCTAssertFalse(DieselTextParser.looksLikeDiesel("Total Loaded Miles 800"))
    }

    func testDieselJournalGroupsASpreadsheetIntoOneWeek() {
        let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
        let early = DieselJournalRow(id: "a", recordedAt: makeDate(2026, 3, 2), sourceFileName: "march.xlsx")
        let later = DieselJournalRow(id: "b", recordedAt: makeDate(2026, 3, 4), sourceFileName: "march.xlsx")
        let lone = DieselJournalRow(id: "c", recordedAt: makeDate(2026, 3, 20))
        let rows = [early, later, lone]
        let anchor = DieselJournalFilter.reportingWeek(of: later, among: rows, week: week)
        XCTAssertEqual(anchor, week.week(for: early.recordedAt))
        XCTAssertEqual(DieselJournalFilter.reportingWeek(of: lone, among: rows, week: week), week.week(for: lone.recordedAt))
        let sliced = DieselJournalFilter.forWeek(rows, weekNumber: anchor.weekNumber, year: anchor.year, week: week)
        XCTAssertEqual(sliced.map(\.id).sorted(), ["a", "b"])
    }

    func testReceiptKindPrefersTheSpecificMarker() {
        XCTAssertEqual(ReceiptKindClassifier.classify("Trip ID T-ABC12345\nTotal Rate $2000"), .load)
        XCTAssertEqual(ReceiptKindClassifier.classify("Driver Settlement\nNet Pay $1200"), .paycheck)
        XCTAssertEqual(ReceiptKindClassifier.classify("Diesel 80 gal PPG 4.10 Pilot"), .diesel)
        XCTAssertEqual(ReceiptKindClassifier.classify("DEF fill 5 gal BlueDEF"), .def)
        XCTAssertEqual(ReceiptKindClassifier.classify("hello"), .unknown)
    }

    func testServiceReceiptPrefersGrandTotalAndSplitsLines() {
        let text = """
        Love's
        Oil change 45.00
        Subtotal $45.00
        Tax $3.60
        Grand Total $48.60
        Date: 03/15/2026
        """
        let parsed = ServiceReceiptParser.parse(text, defaultDate: "2026-01-01")
        XCTAssertEqual(parsed.amount ?? 0, 48.60, accuracy: 0.001)
        XCTAssertEqual(parsed.date, "2026-03-15")
        XCTAssertEqual(parsed.serviceName, "Love's")
        XCTAssertEqual(parsed.lineItems, [ServiceReceiptLine(description: "Oil change", amount: 45)])
    }

    func testPaycheckReadsNetGrossAndSpacedCents() {
        let text = """
        Driver Settlement
        Driver: Jane Doe
        Week Start: 03/01/2026
        Week End: 03/07/2026
        Gross Pay $5,000.00
        Grand Total 4040 30
        """
        let parsed = PaycheckTextParser.parse(text, defaultYear: 2026)
        XCTAssertEqual(parsed?.netAmount ?? 0, 4040.30, accuracy: 0.001)
        XCTAssertEqual(parsed?.grossAmount ?? 0, 5000, accuracy: 0.001)
        XCTAssertEqual(parsed?.driverName, "Jane Doe")
        XCTAssertEqual(parsed?.weekStartDate, "2026-03-01")
        XCTAssertEqual(parsed?.weekEndDate, "2026-03-07")
        XCTAssertEqual(PaycheckSalaryFields.validate(netText: "0"), .net)
        XCTAssertEqual(PaycheckSalaryFields.parseAmount("1,234.50"), 1234.50)
        XCTAssertTrue(PaycheckTextParser.looksLikePaycheck("Net Pay $80.00"))
        XCTAssertFalse(PaycheckTextParser.looksLikePaycheck("Total Loaded Miles 800"))
    }

    func testPaycheckFileNameSuppliesTheWeek() {
        let parsed = PaycheckTextParser.parse("Net Pay $900.00", fileName: "week-3.02-3.08.pdf", defaultYear: 2026)
        XCTAssertEqual(parsed?.netAmount ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(parsed?.weekStartDate, "2026-03-02")
        XCTAssertEqual(parsed?.weekEndDate, "2026-03-08")
    }

    func testPerDiemCountsEachCalendarDayOnce() {
        let loads = [
            LoadSummary.spanning(rate: 1000, from: makeDate(2026, 8, 1), to: makeDate(2026, 8, 3)),
            LoadSummary.spanning(rate: 800, from: makeDate(2026, 8, 3), to: makeDate(2026, 8, 4)),
        ]
        let dates = PerDiemCalculator.uniqueOnDutyDates(
            loads: loads,
            year: 2026,
            today: makeDate(2026, 8, 10),
            calendar: calendar
        )
        XCTAssertEqual(dates, ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04"])
        XCTAssertEqual(PerDiemCalculator.amount(dayCount: dates.count), 276, accuracy: 0.001)
    }

    func testPerDiemToggleMutations() {
        XCTAssertEqual(
            PerDiemDayOverrides.mutationForToggle(isoDate: "2026-08-01", autoDates: ["2026-08-01"], effectiveDates: ["2026-08-01"]),
            .upsertExcluded
        )
        XCTAssertEqual(
            PerDiemDayOverrides.mutationForToggle(isoDate: "2026-08-02", autoDates: [], effectiveDates: ["2026-08-02"]),
            .delete
        )
        XCTAssertEqual(
            PerDiemDayOverrides.mutationForToggle(isoDate: "2026-08-01", autoDates: ["2026-08-01"], effectiveDates: []),
            .delete
        )
        XCTAssertEqual(
            PerDiemDayOverrides.mutationForToggle(isoDate: "2026-08-09", autoDates: [], effectiveDates: []),
            .upsertIncluded
        )
        let applied = PerDiemDayOverrides.apply(
            autoDates: ["2026-08-01", "2026-08-02"],
            snapshot: PerDiemOverrideSnapshot(included: ["2026-08-09"], excluded: ["2026-08-02"])
        )
        XCTAssertEqual(applied, ["2026-08-01", "2026-08-09"])
    }

    func testFederalTaxAndQuarterlyDate() {
        XCTAssertEqual(TaxEstimate.federalTax(20_000), 2_168, accuracy: 0.001)
        XCTAssertEqual(10_000 * 0.153 * 0.9235, TaxEstimate.make(
            grossIncome: 10_000,
            dieselDeductions: 0,
            perDiemDays: 0,
            today: makeDate(2026, 3, 1),
            calendar: calendar
        ).selfEmploymentTax, accuracy: 0.001)
        let quarter = TaxEstimate.nextQuarter(today: makeDate(2026, 3, 1, 10, 0), calendar: calendar)
        XCTAssertEqual(quarter.label, "Q1 4/15")
        XCTAssertGreaterThan(quarter.days, 0)
        let estimate = TaxEstimate.make(
            grossIncome: 10_000,
            dieselDeductions: 1_000,
            perDiemDays: 2,
            today: makeDate(2026, 3, 1),
            calendar: calendar
        )
        XCTAssertEqual(estimate.perDiemAmount, 138, accuracy: 0.001)
        XCTAssertEqual(estimate.taxableIncome, 8_862, accuracy: 0.001)
    }

    func testMiscExpenseValidationAndCsv() {
        XCTAssertEqual(MiscExpenseFields.validate(amountText: "0", description: "Scales", dateISO: "2026-03-15"), .amount)
        XCTAssertEqual(MiscExpenseFields.validate(amountText: "12", description: "  ", dateISO: "2026-03-15"), .description)
        XCTAssertEqual(MiscExpenseFields.validate(amountText: "12", description: "Parking", dateISO: "March"), .date)
        XCTAssertNil(MiscExpenseFields.validate(amountText: "12.50", description: "Parking", dateISO: "2026-03-15"))
        let csv = MiscExpenseFields.csv(rows: [(date: "2026-03-15", description: "Scales, CAT", amount: 12.5, receipt: "yes")])
        XCTAssertTrue(csv.contains("\"Scales, CAT\""))
        XCTAssertTrue(AccountantExport.isEmpty(sections: [.diesel], counts: [.diesel: 0]))
        XCTAssertFalse(AccountantExport.isEmpty(sections: [.all], counts: [.loads: 1]))
    }

    func testFeedbackMailMatchesAndroidDraft() {
        XCTAssertNil(ImprovementFeedbackMail.compose(
            topic: .improve,
            message: "   ",
            topicLabel: "Improve",
            appVersion: "1.5.7 (1)",
            systemName: "Android",
            systemRelease: "14"
        ))
        let draft = ImprovementFeedbackMail.compose(
            topic: .broken,
            message: " Camera fails ",
            topicLabel: "Broken",
            appVersion: "1.5.7 (1)",
            systemName: "Android",
            systemRelease: "14"
        )
        XCTAssertEqual(draft?.to, "Truckorig@gmail.com")
        XCTAssertEqual(draft?.subject, "[TruckoRig] Broken")
        XCTAssertTrue(draft?.body.contains("Тема: Broken") == true)
        XCTAssertTrue(draft?.body.contains("Camera fails") == true)
        XCTAssertTrue(draft?.body.contains("TruckoRig 1.5.7 (1)") == true)
        XCTAssertTrue(draft?.body.contains("Android 14") == true)
        let uri = ImprovementFeedbackMail.mailtoURI(draft!)
        XCTAssertTrue(uri.hasPrefix("mailto:Truckorig@gmail.com?subject="))
        XCTAssertTrue(uri.contains("Camera%20fails"))
        XCTAssertFalse(uri.contains("+"))
    }
}
