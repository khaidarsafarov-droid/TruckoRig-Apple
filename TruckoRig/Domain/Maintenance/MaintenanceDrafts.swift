import Foundation

/// Editor state for a new reminder. Port of `TaskDraft` validation in `MaintenanceViewModel.saveTask`.
public struct MaintenanceTaskDraft: Equatable, Sendable {
    public var title: String
    public var startDate: String
    public var reminderType: MaintenanceReminderType
    public var intervalMiles: String
    public var odometerAtStart: String
    public var dueDate: String

    public init(
        title: String = "",
        startDate: String,
        reminderType: MaintenanceReminderType = .miles,
        intervalMiles: String = "",
        odometerAtStart: String = "",
        dueDate: String
    ) {
        self.title = title
        self.startDate = startDate
        self.reminderType = reminderType
        self.intervalMiles = intervalMiles
        self.odometerAtStart = odometerAtStart
        self.dueDate = dueDate
    }

    public enum Failure: String, Equatable, Sendable, Error {
        case emptyTitle
        case invalidInterval
        case invalidOdometer
        case invalidDueDate
    }

    public func validated(nowMillis: Int64) -> Result<MaintenanceTask, Failure> {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return .failure(.emptyTitle) }
        switch reminderType {
        case .miles:
            guard let interval = DecimalInput.parse(intervalMiles), interval > 0 else {
                return .failure(.invalidInterval)
            }
            guard let odometer = DecimalInput.parse(odometerAtStart), odometer >= 0 else {
                return .failure(.invalidOdometer)
            }
            return .success(MaintenanceTask(
                title: title,
                startDate: startDate,
                reminderType: .miles,
                intervalMiles: interval,
                odometerAtStart: odometer,
                createdAt: nowMillis,
                updatedAt: nowMillis
            ))
        case .date:
            if dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(.invalidDueDate)
            }
            let odometer = DecimalInput.parse(odometerAtStart)
            return .success(MaintenanceTask(
                title: title,
                startDate: startDate,
                reminderType: .date,
                odometerAtStart: odometer,
                dueDate: dueDate,
                createdAt: nowMillis,
                updatedAt: nowMillis
            ))
        }
    }
}

public struct MaintenanceArchiveLineDraft: Equatable, Sendable {
    public var description: String
    public var amount: String

    public init(description: String = "", amount: String = "") {
        self.description = description
        self.amount = amount
    }

    public func parsedAmount() -> Double? { DecimalInput.parse(amount) }
}

/// Port of `ArchiveDraft`.
public struct MaintenanceArchiveDraft: Equatable, Sendable {
    public var serviceName: String
    public var serviceDate: String
    public var lines: [MaintenanceArchiveLineDraft]
    public var photoPath: String?
    public var ocrText: String?

    public init(
        serviceName: String = "",
        serviceDate: String,
        lines: [MaintenanceArchiveLineDraft] = [MaintenanceArchiveLineDraft()],
        photoPath: String? = nil,
        ocrText: String? = nil
    ) {
        self.serviceName = serviceName
        self.serviceDate = serviceDate
        self.lines = lines
        self.photoPath = photoPath
        self.ocrText = ocrText
    }

    public enum Failure: String, Equatable, Sendable {
        case emptyLines
        case emptyDescription
        case invalidAmount
    }

    public func filledLines() -> [MaintenanceArchiveLineDraft] {
        lines.filter {
            !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func validationError() -> Failure? {
        let filled = filledLines()
        if filled.isEmpty { return .emptyLines }
        for line in filled {
            if line.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyDescription }
            guard let amount = line.parsedAmount(), amount >= 0 else { return .invalidAmount }
        }
        return nil
    }

    public func toEntries(createdAt: Int64) -> [MaintenanceArchiveEntry] {
        guard validationError() == nil else { return [] }
        return filledLines().map { line in
            MaintenanceArchiveEntry(
                serviceName: serviceName.trimmingCharacters(in: .whitespacesAndNewlines),
                serviceDate: serviceDate,
                description: line.description.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: MoneyCents.fromDollars(line.parsedAmount() ?? 0),
                photoPath: photoPath,
                ocrText: ocrText,
                createdAt: createdAt
            )
        }
    }

    public static func formatAmount(_ value: Double) -> String {
        value > 0 ? String(format: "%.2f", locale: Locale(identifier: "en_US"), value) : ""
    }
}

/// One-time read of the stage-1 stub row (`dueDate` / `dueOdometer` / `cost` / `notes`).
///
/// The stub was not the Android model. A miles number becomes the interval with odometer 0,
/// because that column stored a single mileage figure and Android's base reading was never
/// captured. A cost or note becomes one archive line so the history is not dropped.
public enum MaintenanceLegacyImport {

    public struct Stub: Equatable, Sendable {
        public var id: String
        public var title: String
        public var dueDateISO: String?
        public var dueOdometer: Int?
        public var completedAtMillis: Int64?
        public var cost: Double?
        public var notes: String?
        public var updatedAtMillis: Int64

        public init(
            id: String,
            title: String,
            dueDateISO: String? = nil,
            dueOdometer: Int? = nil,
            completedAtMillis: Int64? = nil,
            cost: Double? = nil,
            notes: String? = nil,
            updatedAtMillis: Int64
        ) {
            self.id = id
            self.title = title
            self.dueDateISO = dueDateISO
            self.dueOdometer = dueOdometer
            self.completedAtMillis = completedAtMillis
            self.cost = cost
            self.notes = notes
            self.updatedAtMillis = updatedAtMillis
        }
    }

    public struct Imported: Equatable, Sendable {
        public var task: MaintenanceTask
        public var archive: MaintenanceArchiveEntry?
    }

    public static func convert(_ stub: Stub, fallbackStartDate: String) -> Imported {
        let start = stub.dueDateISO ?? fallbackStartDate
        let task: MaintenanceTask
        if let odometer = stub.dueOdometer {
            task = MaintenanceTask(
                id: stub.id,
                title: stub.title,
                startDate: start,
                reminderType: .miles,
                intervalMiles: Double(odometer),
                odometerAtStart: 0,
                isCompleted: stub.completedAtMillis != nil,
                completedAt: stub.completedAtMillis,
                createdAt: stub.updatedAtMillis,
                updatedAt: stub.updatedAtMillis
            )
        } else {
            task = MaintenanceTask(
                id: stub.id,
                title: stub.title,
                startDate: start,
                reminderType: .date,
                dueDate: stub.dueDateISO,
                isCompleted: stub.completedAtMillis != nil,
                completedAt: stub.completedAtMillis,
                createdAt: stub.updatedAtMillis,
                updatedAt: stub.updatedAtMillis
            )
        }
        let notes = stub.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let archive: MaintenanceArchiveEntry?
        if stub.cost != nil || !notes.isEmpty {
            archive = MaintenanceArchiveEntry(
                id: "legacy-\(stub.id)",
                serviceName: "",
                serviceDate: start,
                description: notes.isEmpty ? stub.title : notes,
                amount: MoneyCents.fromDollars(stub.cost ?? 0),
                createdAt: stub.updatedAtMillis
            )
        } else {
            archive = nil
        }
        return Imported(task: task, archive: archive)
    }
}
