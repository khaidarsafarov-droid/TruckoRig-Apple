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
    /// When set, focusing this field publishes `focusTag` so a parent `ScrollViewReader` can scroll to it.
    var focusTag: String?
    var activeFocus: Binding<String?>?

    @FocusState private var isFocused: Bool

    /// Reports focus upward. The text field keeps its own `@FocusState`; the binding is only the scroll id.
    func keyboardFocus(_ tag: String, in active: Binding<String?>) -> Self {
        var copy = self
        copy.focusTag = tag
        copy.activeFocus = active
        return copy
    }

    var body: some View {
        let linked = activeFocus?.wrappedValue
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
                    .strokeBorder(borderColor, lineWidth: showsFocusRing || errorMessage != nil ? 1.5 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: showsFocusRing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            }
        }
        .modifier(FocusTagID(tag: focusTag))
        .accessibilityElement(children: .contain)
        .onChange(of: isFocused) { _, focused in
            guard let focusTag, let activeFocus else { return }
            if focused {
                if activeFocus.wrappedValue != focusTag {
                    activeFocus.wrappedValue = focusTag
                }
            } else if activeFocus.wrappedValue == focusTag {
                activeFocus.wrappedValue = nil
            }
        }
        .onChange(of: linked) { _, newValue in
            guard let focusTag else { return }
            let shouldFocus = newValue == focusTag
            if isFocused != shouldFocus {
                isFocused = shouldFocus
            }
        }
    }

    private var showsFocusRing: Bool {
        if let focusTag, activeFocus?.wrappedValue == focusTag { return true }
        return isFocused
    }

    private var borderColor: Color {
        if errorMessage != nil { return .forestError }
        return showsFocusRing ? .forestPrimary : .clear
    }
}

/// Applies a scroll id only when the field participates in keyboard avoidance.
private struct FocusTagID: ViewModifier {
    var tag: String?

    func body(content: Content) -> some View {
        if let tag {
            content.id(tag)
        } else {
            content
        }
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
    /// Money keeps two fraction digits from whole cents and the app's decimal separator.
    var money = false
    var focusTag: String?
    var activeFocus: Binding<String?>?

    @State private var text: String = ""

    func keyboardFocus(_ tag: String, in active: Binding<String?>) -> Self {
        var copy = self
        copy.focusTag = tag
        copy.activeFocus = active
        return copy
    }

    var body: some View {
        numberField
        .onAppear {
            text = value == 0 ? "" : formatted(value)
        }
        .onChange(of: text) {
            value = parsed(text)
        }
        .onChange(of: value) {
            let current = parsed(text)
            // Only rewrite the field when something other than typing changed the value.
            if abs(current - value) > 0.0001 {
                text = value == 0 ? "" : formatted(value)
            }
        }
    }

    private var numberField: some View {
        let field = SoftTextField(
            title: title,
            text: $text,
            placeholder: placeholder,
            keyboard: allowsDecimal ? .decimalPad : .numberPad
        )
        return Group {
            if let focusTag, let activeFocus {
                field.keyboardFocus(focusTag, in: activeFocus)
            } else {
                field
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        if money {
            return MoneyFieldText.prefill(dollars: value, locale: AppLocale.locale)
        }
        return allowsDecimal && abs(value.rounded() - value) > 0.004
            ? String(format: "%.2f", value)
            : String(format: "%.0f", value)
    }

    private func parsed(_ text: String) -> Double {
        if money {
            return MoneyFieldText.commit(text: text, original: value, locale: AppLocale.locale)
        }
        return NumberParsing.parseMoney(text)
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var amount: Double = 2500

    VStack(spacing: Spacing.standard) {
        SoftTextField(title: "load.tripId", text: $text, placeholder: "T-116KYL6KW", autocapitalization: .characters)
        SoftNumberField(title: "load.totalRate", value: $amount)
        SoftTextField(title: "profile.licensePlate", text: $text, isSecure: true)
    }
    .padding()
    .forestBackground()
}
