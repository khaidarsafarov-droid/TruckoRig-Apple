import Foundation
import SwiftData

/// Single place listing every persisted model.
///
/// The account-scoped container, previews and tests all build from this, so a new `@Model` only
/// has to be registered once.
enum TruckoRigSchema {

    static let models: [any PersistentModel.Type] = [
        Load.self,
        Stop.self,
        Penalty.self,
        Paycheck.self,
        Diesel.self,
        MaintenanceTask.self,
        Photo.self,
        Scan.self,
        DriverProfile.self,
    ]

    static var schema: Schema { Schema(models) }
}
