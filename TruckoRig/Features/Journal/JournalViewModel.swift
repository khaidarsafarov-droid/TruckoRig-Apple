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
        case disputes
        case unfinished
        case yesterday
        case thisWeek
        case lastWeek
        case thisMonth
        case calendarWeek
        case onDate

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: return "journal.filter.all"
            case .disputes: return "journal.filter.disputes"
            case .unfinished: return "journal.filter.unfinished"
            case .yesterday: return "journal.filter.yesterday"
            case .thisWeek: return "journal.filter.thisWeek"
            case .lastWeek: return "journal.filter.lastWeek"
            case .thisMonth: return "journal.filter.thisMonth"
            case .calendarWeek: return "journal.filter.calendarWeek"
            case .onDate: return "journal.filter.onDate"
            }
        }

        var slice: JournalSlice {
            switch self {
            case .all: return .all
            case .disputes: return .disputes
            case .unfinished: return .unfinished
            case .yesterday: return .yesterday
            case .thisWeek: return .thisWeek
            case .lastWeek: return .lastWeek
            case .thisMonth: return .thisMonth
            case .calendarWeek: return .calendarWeek
            case .onDate: return .onDate
            }
        }
    }

    var searchText = ""
    var filter: Filter = .all
    var selectedDay = Date()
    var loadPendingDeletion: Load?
    var errorMessage: String?

    func sections(from loads: [Load], week: TruckingWeek, locale: Locale = .current) -> [JournalSection] {
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
        guard JournalPeriodFilter.includes(
            date: load.date,
            activeDispute: load.isActiveDispute,
            unfinished: unfinished,
            slice: filter.slice,
            selectedDay: selectedDay,
            week: week,
            now: now
        ) else { return false }

        guard !searchText.trimmed.isEmpty else { return true }
        return load.tripId.matchesSearch(searchText)
            || (load.pointA ?? "").matchesSearch(searchText)
            || (load.pointB ?? "").matchesSearch(searchText)
    }

    /// Totals across everything currently visible, for the header summary.
    func visibleTotals(from loads: [Load], week: TruckingWeek) -> LoadTotals {
        LoadTotals.of(loads.filter { matches($0, week: week) }.map(\.summary))
    }
}
