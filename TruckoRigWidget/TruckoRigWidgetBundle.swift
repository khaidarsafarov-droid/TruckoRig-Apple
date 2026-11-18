import SwiftUI
import WidgetKit

@main
struct TruckoRigWidgetBundle: WidgetBundle {
    init() {
        AppLocale.install()
        AppLocale.applyStoredWidgetLanguage()
    }

    var body: some Widget {
        WeeklyGoalWidget()
    }
}
