import SwiftUI
import UIKit

/// Labelled text field with the soft-UI treatment and a focus ring.
struct SoftTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var placeholder: LocalizedStringKey = ""
    var keyboard: UIKeyboardType = .default
    var isSecure = false
    var autocapitalization: TextInputAutocapitalization = .sentences
    var errorMessage: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestTextSecondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.appBody)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(keyboard != .default)
            .focused($isFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.forestSurfaceMuted, in: RoundedRectangle(cornerRadius: Spacing.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.controlRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || errorMessage != nil ? 1.5 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)

            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var borderColor: Color {
        if errorMessage != nil { return .forestError }
        return isFocused ? .forestPrimary : .clear
    }
}

/// Numeric field that keeps a `Double` in step with the driver's typing.
///
/// Bound to text rather than a formatter so a half-typed `12.` does not snap back while the
/// keyboard is still open.
struct SoftNumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var placeholder: LocalizedStringKey = "0"
    var allowsDecimal = true

    @State private var text: String = ""

    var body: some View {
        SoftTextField(
            title: title,
            text: $text,
            placeholder: placeholder,
            keyboard: allowsDecimal ? .decimalPad : .numberPad
        )
        .onAppear {
            text = value == 0 ? "" : formatted(value)
        }
        .onChange(of: text) {
            value = NumberParsing.parseMoney(text)
        }
        .onChange(of: value) {
            let parsed = NumberParsing.parseMoney(text)
            // Only rewrite the field when something other than typing changed the value.
            if abs(parsed - value) > 0.0001 {
                text = value == 0 ? "" : formatted(value)
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        allowsDecimal && abs(value.rounded() - value) > 0.004
            ? String(format: "%.2f", value)
            : String(format: "%.0f", value)
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var amount: Double = 2500

    VStack(spacing: Spacing.standard) {
        SoftTextField(title: "load.tripId", text: $text, placeholder: "T-116KYL6KW", autocapitalization: .characters)
        SoftNumberField(title: "load.totalRate", value: $amount)
        SoftTextField(title: "auth.password", text: $text, isSecure: true)
    }
    .padding()
    .forestBackground()
}
