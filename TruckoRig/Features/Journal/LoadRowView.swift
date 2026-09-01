import SwiftUI

/// One trip in the journal list.
struct LoadRowView: View {
    let load: Load
    var thresholds: RPMThresholds = .default

    private var band: RPMBand {
        RPMCalculator.band(for: load.ratePerMile, thresholds: thresholds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(load.tripId)
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.forestTextSecondary)
                if load.isActiveDispute {
                    Label("load.dispute", systemImage: "exclamationmark.bubble")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.forestWarning)
                        .accessibilityLabel("load.dispute")
                }
                Spacer()
                Text(DateUtils.shortDay(load.date))
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }

            Text(load.route)
                .font(.appBodyMedium)
                .foregroundStyle(Color.forestText)
                .lineLimit(2)

            HStack(spacing: Spacing.standard) {
                Text(Formatters.moneyPrecise(load.totalRate))
                    .font(.appNumber)
                    .foregroundStyle(Color.forestText)

                Text(Formatters.miles(load.totalMiles))
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)

                Spacer()

                Text(Formatters.ratePerMile(load.ratePerMile))
                    .font(.appCaptionMedium)
                    .foregroundStyle(band.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(band.tint.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let pieces = [
            load.tripId,
            load.route,
            Formatters.moneyPrecise(load.totalRate),
            Formatters.ratePerMile(load.ratePerMile),
        ]
        return pieces.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Week header with the week's gross, miles and load count, preceded by a month caption on the
/// first week of each month.
struct WeekHeaderView: View {
    let section: JournalSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let monthMarker = section.monthMarker {
                Text(monthMarker)
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestText)
                    .padding(.top, 8)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.label)
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.forestText)
                    Text("journal.week.summary \(section.loads.count) \(Formatters.miles(section.totals.totalMiles))")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Spacer()
                Text(Formatters.money(section.totals.totalRate))
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.forestPrimary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}
