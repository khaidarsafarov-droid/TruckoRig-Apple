import SwiftUI

/// Privacy Policy and Terms of Use shown on every subscription purchase surface.
enum LegalDocuments {
    static let privacyPolicy = document(
        "https://khaidarsafarov-droid.github.io/truckorig-legal/privacy/"
    )
    static let termsOfUse = document(
        "https://khaidarsafarov-droid.github.io/truckorig-legal/terms/"
    )

    private static func document(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Legal document URL is not valid")
        }
        return url
    }
}

/// Functional links. The same destinations are used on the paywall, in Settings, and in About.
struct LegalDocumentLinks: View {
    var tint: Color = .forestPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            documentLink(LegalDocuments.privacyPolicy, "premium.legal.privacy", id: "legal.privacy")
            documentLink(LegalDocuments.termsOfUse, "premium.legal.terms", id: "legal.terms")
        }
    }

    private func documentLink(_ url: URL, _ title: LocalizedStringKey, id: String) -> some View {
        Link(destination: url) {
            Text(title)
                .font(.appBodyMedium)
                .underline()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tint)
        .accessibilityIdentifier(id)
    }
}

/// Price, period, free trial, and how to cancel. Guideline 3.1.2.
struct SubscriptionLegalNotice: View {
    var priceText: String
    var includesFreeMonth: Bool
    var textColor: Color = .forestTextSecondary
    var linkColor: Color = .forestPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(disclosure)
                .font(.appCaption)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.legal")
            LegalDocumentLinks(tint: linkColor)
        }
    }

    private var disclosure: LocalizedStringKey {
        if includesFreeMonth {
            return "premium.legal.trial \(priceText)"
        }
        return "premium.legal.paid \(priceText)"
    }
}
