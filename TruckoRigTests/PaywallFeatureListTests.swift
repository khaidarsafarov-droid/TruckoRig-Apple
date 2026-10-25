import UIKit
import SwiftUI
import XCTest
@testable import TruckoRig

/// The paywall lists each paid tool, then the free-forever chips.
/// Copy is checked in en, ru, es, and fr. The hosted screen is the same scrollable paywall.
@MainActor
final class PaywallFeatureListTests: XCTestCase {
    func testFeatureOrderSymbolsAndCopy() {
        XCTAssertEqual(
            PaywallFeature.allCases.map(\.rawValue),
            ["telegram", "analytics", "goal", "map", "tax", "scanner", "camera", "export", "fileBackup"]
        )
        XCTAssertEqual(
            PaywallFeature.allCases.map(\.symbol),
            [
                "paperplane.fill",
                "chart.line.uptrend.xyaxis",
                "flag.fill",
                "map.fill",
                "receipt",
                "doc.viewfinder",
                "camera.fill",
                "square.and.arrow.down",
                "doc.on.doc.fill",
            ]
        )
        XCTAssertFalse(PaywallFeature.fileBackup.symbol.localizedCaseInsensitiveContains("cloud"))
        XCTAssertEqual(
            PaywallFreeTool.allCases.map(\.rawValue),
            ["loads", "diesel", "pay", "deadhead"]
        )

        for (feature, copy) in zip(PaywallFeature.allCases, Self.features) {
            for (locale, title, benefit) in copy {
                XCTAssertEqual(Self.text(feature.titleKeyName, locale: locale), title, locale)
                XCTAssertEqual(Self.text(feature.benefitKeyName, locale: locale), benefit, locale)
                let combined = title + " " + benefit
                XCTAssertFalse(combined.localizedCaseInsensitiveContains("Google Drive"), combined)
                XCTAssertFalse(combined.localizedCaseInsensitiveContains("Drive folder"), combined)
            }
        }
        for (tool, copy) in zip(PaywallFreeTool.allCases, Self.freeTools) {
            for (locale, title) in copy {
                XCTAssertEqual(Self.text(tool.titleKeyName, locale: locale), title, locale)
            }
        }
        for (locale, title) in Self.includedTitle {
            XCTAssertEqual(Self.text("premium.included.title", locale: locale), title, locale)
        }
        for (locale, title) in Self.freeTitle {
            XCTAssertEqual(Self.text("premium.free.title", locale: locale), title, locale)
        }
        for (locale, body) in Self.body {
            let resolved = Self.text("premium.body", locale: locale)
            XCTAssertEqual(resolved, body, locale)
            XCTAssertFalse(resolved.contains("Telegram"), resolved)
            XCTAssertFalse(resolved.localizedCaseInsensitiveContains("scanner"), resolved)
            XCTAssertFalse(resolved.localizedCaseInsensitiveContains("Google"), resolved)
        }
    }

    func testFeatureRowsRenderOnSEAtAccessibilitySize() async {
        let width: CGFloat = 320
        let height: CGFloat = 568
        let host = UIHostingController(
            rootView: PaywallView(
                priceText: "$2.99",
                includesFreeMonth: true,
                isLoading: false,
                safeAreaBottom: 48,
                keyboardHeight: 0,
                onSubscribe: {},
                onRestore: {},
                onClose: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "en"))
        )
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        UIView.setAnimationsEnabled(false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 400_000_000)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        var nodes: [(id: String, label: String)] = []
        collect(host.view, into: &nodes)
        let labels = nodes.map(\.label).joined(separator: "\n")
        let ids = nodes.map(\.id).filter { !$0.isEmpty }

        XCTAssertTrue(ids.contains("paywall.body"), "ids: \(ids)")
        let body = nodes.first { $0.id == "paywall.body" }?.label ?? ""
        XCTAssertTrue(body.contains("$2.99"), body)
        XCTAssertFalse(body.contains("Telegram"), body)
        XCTAssertTrue(ids.contains("paywall.included"), "ids: \(ids)")
        XCTAssertTrue(ids.contains("paywall.free.title"), "ids: \(ids)")
        XCTAssertTrue(ids.contains("paywall.subscribe"), "ids: \(ids)")

        let featureIDs = PaywallFeature.allCases.map(\.accessibilityID)
        let renderedFeatures = ids.filter { featureIDs.contains($0) }
        XCTAssertEqual(renderedFeatures, featureIDs, "feature rows out of order in \(ids)")

        for (feature, copy) in zip(PaywallFeature.allCases, Self.features) {
            let english = copy.first { $0.0 == "en" }!
            let label = nodes.first { $0.id == feature.accessibilityID }?.label ?? ""
            XCTAssertTrue(label.contains(english.1), "title missing from \(label)")
            XCTAssertTrue(label.contains(english.2), "benefit missing from \(label)")
        }
        for tool in PaywallFreeTool.allCases {
            XCTAssertTrue(ids.contains(tool.accessibilityID), "missing \(tool.accessibilityID) in \(ids)")
        }
        XCTAssertTrue(labels.localizedCaseInsensitiveContains("Free forever"), labels)
        XCTAssertFalse(labels.localizedCaseInsensitiveContains("Google Drive"), labels)
        window.isHidden = true
    }

    private func collect(_ view: UIView, into nodes: inout [(id: String, label: String)]) {
        let id = view.accessibilityIdentifier ?? ""
        let label = view.accessibilityLabel ?? ""
        if !id.isEmpty || !label.isEmpty {
            nodes.append((id, label))
        }
        for subview in view.subviews {
            collect(subview, into: &nodes)
        }
    }

    private static func text(_ key: String, locale: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: Bundle(for: PaywallLayoutProbe.self),
            locale: Locale(identifier: locale)
        )
    }

    private static let includedTitle: [(String, String)] = [
        ("en", "What's included in Premium"),
        ("ru", "Что входит в Premium"),
        ("es", "Qué incluye Premium"),
        ("fr", "Ce qui est inclus dans Premium"),
    ]

    private static let freeTitle: [(String, String)] = [
        ("en", "Free forever"),
        ("ru", "Бесплатно навсегда"),
        ("es", "Gratis para siempre"),
        ("fr", "Gratuit pour toujours"),
    ]

    private static let body: [(String, String)] = [
        ("en", "The first month is free. After that, the App Store charges the monthly price on the button — $2.99 in the United States."),
        ("ru", "Первый месяц бесплатно. Дальше App Store списывает цену на кнопке — в США это 2,99 $ в месяц."),
        ("es", "El primer mes es gratis. Después, el App Store cobra el precio del botón: 2,99 $ al mes en Estados Unidos."),
        ("fr", "Le premier mois est gratuit. Ensuite, l'App Store facture le prix mensuel indiqué sur le bouton — 2,99 $ aux États-Unis."),
    ]

    /// locale, title, benefit. Order matches `PaywallFeature.allCases`.
    private static let features: [[(String, String, String)]] = [
        [
            ("en", "Telegram import", "Broker messages land in the journal as loads."),
            ("ru", "Импорт из Telegram", "Сообщения брокера попадают в журнал как грузы."),
            ("es", "Importación de Telegram", "Los mensajes del broker entran al diario como cargas."),
            ("fr", "Importation Telegram", "Les messages du courtier arrivent au journal comme chargements."),
        ],
        [
            ("en", "Analytics", "Gross, miles, and rate per mile for the period."),
            ("ru", "Аналитика", "Гросс, мили и ставка за милю за период."),
            ("es", "Analítica", "Bruto, millas y tarifa por milla del período."),
            ("fr", "Analyses", "Brut, miles et taux au mile pour la période."),
        ],
        [
            ("en", "Weekly goal", "Gross still needed before the week ends."),
            ("ru", "Недельная цель", "Сколько гросса ещё нужно до конца недели."),
            ("es", "Meta semanal", "El bruto que aún te falta antes de cerrar la semana."),
            ("fr", "Objectif hebdomadaire", "Le brut qu'il vous reste avant la fin de la semaine."),
        ],
        [
            ("en", "Map", "Outbound rate per mile by state before you book."),
            ("ru", "Карта", "Ставка за милю из штата до того, как взять груз."),
            ("es", "Mapa", "Tarifa por milla de salida por estado, antes de tomar la carga."),
            ("fr", "Carte", "Taux au mile au départ, par État, avant de prendre le chargement."),
        ],
        [
            ("en", "Taxes", "Quarterly estimate from income, diesel, and per diem."),
            ("ru", "Налоги", "Оценка квартала по доходу, дизелю и per diem."),
            ("es", "Impuestos", "Estimación trimestral: ingreso, diésel y per diem."),
            ("fr", "Impôts", "Estimation trimestrielle : revenu, diesel et per diem."),
        ],
        [
            ("en", "Scanner", "Rate confirmations and receipts filed from the cab."),
            ("ru", "Сканер", "Подтверждения ставки и чеки из кабины."),
            ("es", "Escáner", "Confirmaciones de tarifa y recibos desde la cabina."),
            ("fr", "Numériseur", "Confirmations de taux et reçus classés depuis la cabine."),
        ],
        [
            ("en", "Camera", "Pickup and delivery photos stamped with the stop location."),
            ("ru", "Камера", "Фото погрузки и выгрузки с координатами остановки."),
            ("es", "Cámara", "Fotos de recogida y entrega con la ubicación de la parada."),
            ("fr", "Caméra", "Photos de cueillette et de livraison avec l'emplacement de l'arrêt."),
        ],
        [
            ("en", "Export", "The journal downloaded as a CSV."),
            ("ru", "Экспорт", "Журнал в файле CSV для отчётности."),
            ("es", "Exportación", "El diario descargado como CSV."),
            ("fr", "Exportation", "Le journal téléchargé en CSV."),
        ],
        [
            ("en", "Backup to file", "A copy of the log you can restore on Android or iPhone."),
            ("ru", "Бэкап в файл", "Копия журнала, которую можно восстановить на Android и iPhone."),
            ("es", "Respaldo en archivo", "Una copia del diario que puedes restaurar en Android o iPhone."),
            ("fr", "Sauvegarde dans un fichier", "Une copie du journal que vous pouvez restaurer sur Android ou iPhone."),
        ],
    ]

    private static let freeTools: [[(String, String)]] = [
        [("en", "Loads"), ("ru", "Грузы"), ("es", "Cargas"), ("fr", "Chargements")],
        [("en", "Diesel"), ("ru", "Дизель"), ("es", "Diésel"), ("fr", "Diesel")],
        [("en", "Paychecks"), ("ru", "Зарплаты"), ("es", "Pagos"), ("fr", "Chèques de paie")],
        [("en", "Deadhead"), ("ru", "Deadhead"), ("es", "Deadhead"), ("fr", "Deadhead")],
    ]
}
