import Foundation
import SwiftUI

/// Miles and kilometers already have catalog keys. Screens ask here instead of branching again.
enum UnitCopy {
    static func distanceStat(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "stat.miles"
        case .kilometers: return "stat.kilometers"
        }
    }

    static func homeDistance(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "home.stat.miles"
        case .kilometers: return "home.stat.kilometers"
        }
    }

    static func homeRate(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "home.stat.rpm"
        case .kilometers: return "home.stat.perKilometer"
        }
    }

    static func totalDistance(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "load.totalMiles"
        case .kilometers: return "load.totalKilometers"
        }
    }

    static func settingsUnit(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "settings.units.miles"
        case .kilometers: return "settings.units.kilometers"
        }
    }

    static func settingsRate(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "settings.rpm"
        case .kilometers: return "settings.rpm.perKilometer"
        }
    }

    static func maintenanceBasis(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "maintenance.byMiles"
        case .kilometers: return "maintenance.byKilometers"
        }
    }

    static func maintenanceInterval(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "maintenance.interval"
        case .kilometers: return "maintenance.interval.kilometers"
        }
    }

    static func maintenanceOdometer(_ system: MeasurementSystem) -> LocalizedStringKey {
        switch system {
        case .miles: return "maintenance.odometer.current"
        case .kilometers: return "maintenance.odometer.current.kilometers"
        }
    }

    static func maintenanceIntervalError(_ system: MeasurementSystem) -> String {
        switch system {
        case .miles: return "maintenance.error.interval"
        case .kilometers: return "maintenance.error.kilometers"
        }
    }

    static func maintenanceOdometerError(_ system: MeasurementSystem) -> String {
        switch system {
        case .miles: return "maintenance.error.odometer"
        case .kilometers: return "maintenance.error.odometer.kilometers"
        }
    }

    static func maintenanceProgress(driven: String, loads: Int, remaining: String, system: MeasurementSystem) -> String {
        switch system {
        case .miles:
            return String(localized: "maintenance.miles.progress \(driven) \(loads) \(remaining)")
        case .kilometers:
            return String(localized: "maintenance.kilometers.progress \(driven) \(loads) \(remaining)")
        }
    }

    static func maintenanceOdometerEstimate(current: String, target: String, system: MeasurementSystem) -> String {
        switch system {
        case .miles:
            return String(localized: "maintenance.odometer.estimate \(current) \(target)")
        case .kilometers:
            return String(localized: "maintenance.odometer.estimate.km \(current) \(target)")
        }
    }

    static func mapStateAverage(rpm: String, trips: Int, system: MeasurementSystem) -> String {
        switch system {
        case .miles:
            return String(localized: "map.state.avg \(rpm) \(trips)")
        case .kilometers:
            return String(localized: "map.state.avg.km \(rpm) \(trips)")
        }
    }

    static func mapLane(from: String, to: String, rpm: String, trips: Int, system: MeasurementSystem) -> String {
        switch system {
        case .miles:
            return String(localized: "map.lane \(from) \(to) \(rpm) \(trips)")
        case .kilometers:
            return String(localized: "map.lane.km \(from) \(to) \(rpm) \(trips)")
        }
    }

    static func mapRecent(from: String, to: String, rpm: String, age: String, system: MeasurementSystem) -> String {
        switch system {
        case .miles:
            return String(localized: "map.recent \(from) \(to) \(rpm) \(age)")
        case .kilometers:
            return String(localized: "map.recent.km \(from) \(to) \(rpm) \(age)")
        }
    }

    static func mapDetailRate(rpm: String, system: MeasurementSystem) -> String {
        switch system {
        case .miles:
            return String(localized: "map.detail.rpm \(rpm)")
        case .kilometers:
            return String(localized: "map.detail.perKilometer \(rpm)")
        }
    }
}
