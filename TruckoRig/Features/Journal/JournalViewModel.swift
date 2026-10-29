import Foundation
import Observation
import SwiftUI

/// One week of loads in the journal list.
struct JournalSection: Identifiable {
    let week: WeekRef
    let label: String
    /// `"August 2025"`, set only on the first week of each month so the list reads
    /// year → month → week without nested sections.
    let monthMarker: String?
    let loads: [Load]

    var id: WeekRef { week }

    var totals: LoadTotals { LoadTotals.of(loads.map(\.summary)) }
}

/// Search, filtering and week grouping for the journal.
///
/// Takes the catalog from the view rather than fetching itself, so this stays a pure
/// transformation that can be reasoned about on its own.
@Observable
final class JournalViewModel {

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case today
        case disputes
        case unfinished
        case yesterday
        case thisWeek
        case lastWeek
        case thisMonth
        case calendarWeek
        case onDate
        case dateRange

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: return "journal.filter.all"
            case .today: return "journal.filter.today"
            case .disputes: return "journal.filter.disputes"
            case .unfinished: return "journal.filter.unfinished"
            case .yesterday: return "journal.filter.yesterday"
            case .thisWeek: return "journal.filter.thisWeek"
            case .lastWeek: return "journal.filter.lastWeek"
            case .thisMonth: return "journal.filter.thisMonth"
            case .calendarWeek: return "journal.filter.calendarWeek"
            case .onDate: return "journal.filter.onDate"
            case .dateRange: return "journal.filter.range"
            }
        }

        var slice: JournalSlice {
            switch self {
            case .all: return .all
            case .today: return .onDate
            case .disputes: return .disputes
            case .unfinished: return .unfinished
            case .yesterday: return .yesterday
            case .thisWeek: return .thisWeek
            case .lastWeek: return .lastWeek
            case .thisMonth: return .thisMonth
            case .calendarWeek: return .calendarWeek
            case .onDate: return .onDate
            case .dateRange: return .dateRange
            }
        }
    }

    var searchText = ""
    var filter: Filter = .all
    var selectedDay = Date()
    var rangeStart = Date()
    var rangeEnd = Date()
    var loadPendingDeletion: Load?
    var errorMessage: String?

    func sections(from loads: [Load], week: TruckingWeek, locale: Locale = AppLocale.locale) -> [JournalSection] {
        let formatter = WeekLabelFormatter(week: week, locale: locale)
        let filtered = loads.filter { matches($0, week: week) }
        let grouped = Dictionary(grouping: filtered) { WeekRef(weekNumber: $0.weekNumber, year: $0.year) }

        let orderedWeeks = grouped.keys.sorted(by: >)
        return orderedWeeks.enumerated().map { index, ref in
            let previous = index > 0 ? orderedWeeks[index - 1] : nil
            return JournalSection(
                week: ref,
                label: formatter.label(for: ref),
                monthMarker: formatter.monthMarker(for: ref, after: previous),
                loads: (grouped[ref] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    func matches(_ load: Load, week: TruckingWeek, now: Date = Date()) -> Bool {
        let unfinished = load.lastDeliveryAt == nil && load.actualFinishDate == nil
        let finish = load.effectiveFinishDate
        guard JournalPeriodFilter.includes(
            date: load.date,
            activeDispute: load.isActiveDispute,
            unfinished: unfinished,
            slice: filter.slice,
            selectedDay: filter == .today ? now : selectedDay,
            week: week,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: now,
            end: finish,
            reportingWeek: WeekRef(weekNumber: load.weekNumber, year: load.year)
        ) else { return false }

        let calendar = week.calendar
        let days = JournalPeriodFilter.activeDays(from: load.date, through: finish, calendar: calendar)
        let isoDates = days.map { MaintenanceMileage.isoDay($0, calendar: calendar) }
        let displayDates = days.flatMap { day -> [String] in
            let month = calendar.component(.month, from: day)
            let number = calendar.component(.day, from: day)
            let year = calendar.component(.year, from: day)
            return [
                "\(month)/\(number)",
                String(format: "%02d.%02d", number, month),
                String(format: "%02d.%02d.%04d", number, month, year),
                DateUtils.weekdayShortDay(day),
                DateUtils.mediumDate(day)
            ]
        }
        let places = [load.pointA, load.pointB].compactMap { $0 } + (load.stops ?? []).flatMap { stop in
            [stop.city, stop.state, stop.cityState, stop.fullAddress, stop.facility ?? ""]
        }
        return JournalSearch.matches(
            query: searchText,
            tripId: load.tripId,
            places: places,
            isoDates: isoDates,
            displayDates: displayDates
        )
    }

    /// Totals across everything currently visible, for the header summary.
    func visibleTotals(from loads: [Load], week: TruckingWeek) -> LoadTotals {
        LoadTotals.of(loads.filter { matches($0, week: week) }.map(\.summary))
    }
}
