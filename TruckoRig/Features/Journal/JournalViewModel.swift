import Foundation
import Observation
import SwiftUI

/// One week of loads in the journal list.
struct JournalSection: Identifiable {
    let week: WeekRef
    let label: String
    let loads: [Load]

    var id: WeekRef { week }

    var totals: LoadTotals { LoadTotals.of(loads.map(\.summary)) }
    /// Shown on the header when the week starts a new year.
    var yearLabel: String { String(week.year) }
}

/// Search, filtering and week grouping for the journal.
///
/// Takes the `@Query` results from the view rather than fetching itself, so SwiftData still drives
/// updates and this stays a pure transformation that can be reasoned about on its own.
@Observable
final class JournalViewModel {

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case disputes
        case unfinished

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: return "journal.filter.all"
            case .disputes: return "journal.filter.disputes"
            case .unfinished: return "journal.filter.unfinished"
            }
        }
    }

    var searchText = ""
    var filter: Filter = .all
    var loadPendingDeletion: Load?
    var errorMessage: String?

    func sections(from loads: [Load], week: TruckingWeek, locale: Locale = .current) -> [JournalSection] {
        let formatter = WeekLabelFormatter(week: week, locale: locale)
        let filtered = loads.filter(matches)
        let grouped = Dictionary(grouping: filtered) { WeekRef(weekNumber: $0.weekNumber, year: $0.year) }

        return grouped
            .map { ref, loads in
                JournalSection(
                    week: ref,
                    label: formatter.label(for: ref),
                    loads: loads.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.week > $1.week }
    }

    func matches(_ load: Load) -> Bool {
        switch filter {
        case .all: break
        case .disputes where !load.isActiveDispute: return false
        case .unfinished where load.lastDeliveryAt != nil || load.actualFinishDate != nil: return false
        default: break
        }

        guard !searchText.trimmed.isEmpty else { return true }
        return load.tripId.matchesSearch(searchText)
            || (load.pointA ?? "").matchesSearch(searchText)
            || (load.pointB ?? "").matchesSearch(searchText)
    }

    /// Totals across everything currently visible, for the header summary.
    func visibleTotals(from loads: [Load]) -> LoadTotals {
        LoadTotals.of(loads.filter(matches).map(\.summary))
    }
}
