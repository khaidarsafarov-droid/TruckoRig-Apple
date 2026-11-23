import Foundation

/// Captions baked into the report. The share sheet's chrome lives in the string catalog;
/// the file a dispatcher receives cannot depend on that catalog being loaded.
struct PeriodReportCopy: Equatable, Sendable {
    var brand: String
    var driver: String
    var period: String
    var generated: String
    var summary: String
    var loadsSection: String
    var gross: String
    var loadCount: String
    var miles: String
    var kilometers: String
    var loadedMiles: String
    var loadedKilometers: String
    var emptyMiles: String
    var emptyKilometers: String
    var averageRate: String
    var fuel: String
    var expenses: String
    var penalties: String
    var net: String
    var weeklyGoal: String
    var goalProgress: String
    var goalOf: String
    var route: String
    var loadNumber: String
    var rate: String
    var ratePerMile: String
    var ratePerKilometer: String
    var status: String
    var source: String
    var equipment: String
    var notes: String
    var statusInProgress: String
    var statusDelivered: String
    var statusDisputeOpen: String
    var statusDisputeSettled: String
    var sourceRelay: String
    var sourceManual: String
    var sourceBroker: String
    var emptyLoads: String
    var footer: String
    var week: String
    var gallons: String
    var liters: String
    var statementTitle: String
    var originHeader: String
    var destinationHeader: String
    var shipHeader: String
    var deliveryHeader: String
    var grossHeader: String
    var rateHeaderMiles: String
    var rateHeaderKilometers: String
    var total: String
    var loadsTotal: String
    var grossTotal: String
    var milesTotal: String
    var equipmentNames: [String: String]

    func rateColumn(_ system: MeasurementSystem) -> String {
        system == .kilometers ? rateHeaderKilometers : rateHeaderMiles
    }

    func distance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? kilometers : miles
    }

    func loadedDistance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? loadedKilometers : loadedMiles
    }

    func emptyDistance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? emptyKilometers : emptyMiles
    }

    func ratePerDistance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? ratePerKilometer : ratePerMile
    }

    func volumeUnit(_ system: MeasurementSystem) -> String {
        system == .kilometers ? liters : gallons
    }

    func goalProgressValue(percent: Int, gross: String, target: String) -> String {
        "\(percent)% (\(gross) \(goalOf) \(target))"
    }

    func equipmentName(_ code: String?) -> String? {
        guard let code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let known = EquipmentType.fromStorage(trimmed) {
            return equipmentNames[known.rawValue] ?? known.rawValue
        }
        return trimmed
    }

    static func resolve(_ language: PeriodReportLanguage) -> PeriodReportCopy {
        switch language {
        case .english: return english
        case .russian: return russian
        case .french: return french
        case .spanish: return spanish
        }
    }

    static let english = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Driver",
        period: "Period",
        generated: "Generated",
        summary: "Summary",
        loadsSection: "Loads",
        gross: "Gross revenue",
        loadCount: "Number of loads",
        miles: "Miles",
        kilometers: "Kilometers",
        loadedMiles: "Loaded miles",
        loadedKilometers: "Loaded kilometers",
        emptyMiles: "Empty miles",
        emptyKilometers: "Empty kilometers",
        averageRate: "Average rate",
        fuel: "Fuel",
        expenses: "Expenses",
        penalties: "Penalties",
        net: "Net",
        weeklyGoal: "Goal",
        goalProgress: "Goal progress",
        goalOf: "of",
        route: "Route",
        loadNumber: "Load #",
        rate: "Rate",
        ratePerMile: "Rate per mile",
        ratePerKilometer: "Rate per kilometer",
        status: "Status",
        source: "Source",
        equipment: "Equipment",
        notes: "Notes",
        statusInProgress: "In progress",
        statusDelivered: "Delivered",
        statusDisputeOpen: "Dispute open",
        statusDisputeSettled: "Dispute settled",
        sourceRelay: "Amazon Relay",
        sourceManual: "Manual",
        sourceBroker: "Broker",
        emptyLoads: "No loads in this period.",
        footer: "Only on this device",
        week: "Week",
        gallons: "gal",
        liters: "L",
        statementTitle: "Load Report",
        originHeader: "Origin",
        destinationHeader: "Destination",
        shipHeader: "Ship date",
        deliveryHeader: "Delivery",
        grossHeader: "Gross",
        rateHeaderMiles: "Rate/mi",
        rateHeaderKilometers: "Rate/km",
        total: "Total",
        loadsTotal: "Loads total",
        grossTotal: "Gross total",
        milesTotal: "Miles total",
        equipmentNames: [
            "DRY_VAN": "Dry van",
            "REEFER": "Reefer",
            "FLATBED": "Flatbed",
            "POWER_ONLY": "Power only",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Box truck",
            "CARGO_VAN": "Cargo van",
            "OTHER": "Other",
        ]
    )

    static let russian = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Водитель",
        period: "Период",
        generated: "Создан",
        summary: "Сводка",
        loadsSection: "Грузы",
        gross: "Валовая выручка",
        loadCount: "Число грузов",
        miles: "Мили",
        kilometers: "Километры",
        loadedMiles: "Мили с грузом",
        loadedKilometers: "Километры с грузом",
        emptyMiles: "Порожние мили",
        emptyKilometers: "Порожние километры",
        averageRate: "Средняя ставка",
        fuel: "Топливо",
        expenses: "Расходы",
        penalties: "Штрафы",
        net: "Чистыми",
        weeklyGoal: "Цель",
        goalProgress: "Прогресс цели",
        goalOf: "из",
        route: "Маршрут",
        loadNumber: "№ груза",
        rate: "Ставка",
        ratePerMile: "Ставка за милю",
        ratePerKilometer: "Ставка за километр",
        status: "Статус",
        source: "Источник",
        equipment: "Оборудование",
        notes: "Заметки",
        statusInProgress: "В пути",
        statusDelivered: "Доставлен",
        statusDisputeOpen: "Спор открыт",
        statusDisputeSettled: "Спор закрыт",
        sourceRelay: "Amazon Relay",
        sourceManual: "Вручную",
        sourceBroker: "Брокер",
        emptyLoads: "В этом периоде нет грузов.",
        footer: "Только на этом устройстве",
        week: "Неделя",
        gallons: "гал",
        liters: "л",
        statementTitle: "Отчёт по грузам",
        originHeader: "Откуда",
        destinationHeader: "Куда",
        shipHeader: "Загрузка",
        deliveryHeader: "Выгрузка",
        grossHeader: "Сумма",
        rateHeaderMiles: "$/миля",
        rateHeaderKilometers: "$/км",
        total: "Итого",
        loadsTotal: "Всего грузов",
        grossTotal: "Валовая сумма",
        milesTotal: "Всего миль",
        equipmentNames: [
            "DRY_VAN": "Сухой фургон",
            "REEFER": "Рефрижератор",
            "FLATBED": "Площадка",
            "POWER_ONLY": "Только тягач",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Фургон",
            "CARGO_VAN": "Грузовой фургон",
            "OTHER": "Другое",
        ]
    )

    static let french = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Conducteur",
        period: "Période",
        generated: "Créé le",
        summary: "Sommaire",
        loadsSection: "Voyages",
        gross: "Revenu brut",
        loadCount: "Nombre de voyages",
        miles: "Milles",
        kilometers: "Kilomètres",
        loadedMiles: "Milles chargés",
        loadedKilometers: "Kilomètres chargés",
        emptyMiles: "Milles à vide",
        emptyKilometers: "Kilomètres à vide",
        averageRate: "Taux moyen",
        fuel: "Carburant",
        expenses: "Dépenses",
        penalties: "Pénalités",
        net: "Net",
        weeklyGoal: "Objectif",
        goalProgress: "Progression",
        goalOf: "sur",
        route: "Trajet",
        loadNumber: "N° de voyage",
        rate: "Taux",
        ratePerMile: "Taux au mille",
        ratePerKilometer: "Taux au kilomètre",
        status: "Statut",
        source: "Source",
        equipment: "Équipement",
        notes: "Notes",
        statusInProgress: "En cours",
        statusDelivered: "Livré",
        statusDisputeOpen: "Litige ouvert",
        statusDisputeSettled: "Litige réglé",
        sourceRelay: "Amazon Relay",
        sourceManual: "Manuel",
        sourceBroker: "Courtier",
        emptyLoads: "Aucun voyage pour cette période.",
        footer: "Uniquement sur cet appareil",
        week: "Semaine",
        gallons: "gal",
        liters: "L",
        statementTitle: "Rapport des voyages",
        originHeader: "Origine",
        destinationHeader: "Destination",
        shipHeader: "Enlèvement",
        deliveryHeader: "Livraison",
        grossHeader: "Brut",
        rateHeaderMiles: "$/mille",
        rateHeaderKilometers: "$/km",
        total: "Total",
        loadsTotal: "Voyages au total",
        grossTotal: "Brut total",
        milesTotal: "Milles au total",
        equipmentNames: [
            "DRY_VAN": "Fourgon sec",
            "REEFER": "Frigorifique",
            "FLATBED": "Plateau",
            "POWER_ONLY": "Tracteur seul",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Camion fourgon",
            "CARGO_VAN": "Fourgonnette",
            "OTHER": "Autre",
        ]
    )

    static let spanish = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Conductor",
        period: "Período",
        generated: "Generado",
        summary: "Resumen",
        loadsSection: "Cargas",
        gross: "Ingreso bruto",
        loadCount: "Número de cargas",
        miles: "Millas",
        kilometers: "Kilómetros",
        loadedMiles: "Millas cargadas",
        loadedKilometers: "Kilómetros cargados",
        emptyMiles: "Millas vacías",
        emptyKilometers: "Kilómetros vacíos",
        averageRate: "Tarifa media",
        fuel: "Combustible",
        expenses: "Gastos",
        penalties: "Penalizaciones",
        net: "Neto",
        weeklyGoal: "Meta",
        goalProgress: "Progreso de la meta",
        goalOf: "de",
        route: "Ruta",
        loadNumber: "N.º de carga",
        rate: "Tarifa",
        ratePerMile: "Tarifa por milla",
        ratePerKilometer: "Tarifa por kilómetro",
        status: "Estado",
        source: "Origen",
        equipment: "Equipo",
        notes: "Notas",
        statusInProgress: "En curso",
        statusDelivered: "Entregada",
        statusDisputeOpen: "Disputa abierta",
        statusDisputeSettled: "Disputa cerrada",
        sourceRelay: "Amazon Relay",
        sourceManual: "Manual",
        sourceBroker: "Bróker",
        emptyLoads: "No hay cargas en este período.",
        footer: "Solo en este dispositivo",
        week: "Semana",
        gallons: "gal",
        liters: "L",
        statementTitle: "Informe de cargas",
        originHeader: "Origen",
        destinationHeader: "Destino",
        shipHeader: "Carga",
        deliveryHeader: "Entrega",
        grossHeader: "Bruto",
        rateHeaderMiles: "$/milla",
        rateHeaderKilometers: "$/km",
        total: "Total",
        loadsTotal: "Cargas en total",
        grossTotal: "Bruto total",
        milesTotal: "Millas en total",
        equipmentNames: [
            "DRY_VAN": "Caja seca",
            "REEFER": "Refrigerado",
            "FLATBED": "Plataforma",
            "POWER_ONLY": "Solo tracto",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Camión caja",
            "CARGO_VAN": "Furgoneta",
            "OTHER": "Otro",
        ]
    )
}
