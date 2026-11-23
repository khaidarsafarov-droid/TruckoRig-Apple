import Foundation
import GRDB

/// Driver profile row.
extension AppDatabase {
    static func fetchProfile(_ db: Database) throws -> DriverProfile? {
        try Row.fetchOne(db, sql: "SELECT * FROM profile LIMIT 1").map(profile(from:))
    }


    static func upsert(_ db: Database, _ profile: DriverProfile) throws {
        try execute(db, """
        INSERT INTO profile (
            id, name, truckModel, truckYear, licensePlate, homeState, preferredLanguage,
            weeklyGoal, updatedAt
        ) VALUES (\(marks(9)))
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name, truckModel = excluded.truckModel,
            truckYear = excluded.truckYear, licensePlate = excluded.licensePlate, homeState = excluded.homeState,
            preferredLanguage = excluded.preferredLanguage, weeklyGoal = excluded.weeklyGoal,
            updatedAt = excluded.updatedAt
        """, [
            profile.id.uuidString, profile.name, profile.truckModel, profile.truckYear,
            profile.licensePlate, profile.homeState, profile.preferredLanguage.rawValue, profile.weeklyGoal,
            profile.updatedAt.timeIntervalSince1970,
        ])
    }


    static func profile(from row: Row) -> DriverProfile {
        let rawLanguage = string(row, "preferredLanguage") ?? AppLanguage.system.rawValue
        return DriverProfile(
            id: uuid(row, "id") ?? UUID(),
            name: string(row, "name"),
            truckModel: string(row, "truckModel"),
            truckYear: int(row, "truckYear"),
            licensePlate: string(row, "licensePlate"),
            homeState: string(row, "homeState"),
            preferredLanguage: AppLanguage(rawValue: rawLanguage) ?? .system,
            weeklyGoal: double(row, "weeklyGoal") ?? 0,
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }
}
