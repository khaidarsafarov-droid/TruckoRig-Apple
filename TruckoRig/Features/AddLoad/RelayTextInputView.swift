import SwiftUI

/// Paste area for Relay text, with the parse result reported inline.
struct RelayTextInputView: View {

    @Binding var text: String
    var parseMessage: String?
    var errorMessage: String?
    let onParse: () -> Void
    let onClear: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("relay.paste.title")
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)

            Text("relay.paste.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)

            TextEditor(text: $text)
                .font(.appCallout)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    Color.forestSurfaceMuted,
                    in: RoundedRectangle(cornerRadius: Spacing.controlRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.controlRadius, style: .continuous)
                        .strokeBorder(isFocused ? Color.forestPrimary : .clear, lineWidth: 1.5)
                )
                .focused($isFocused)
                .accessibilityLabel("relay.paste.title")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            } else if let parseMessage {
                Label(parseMessage, systemImage: "checkmark.circle")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestSuccess)
            }

            HStack(spacing: Spacing.tight) {
                SoftButton(title: "relay.paste.parse", systemImage: "wand.and.stars") {
                    isFocused = false
                    onParse()
                }
                .disabled(text.trimmed.isEmpty)

                if !text.isEmpty {
                    SoftButton(title: "action.clear", role: .secondary, action: onClear)
                        .frame(maxWidth: 120)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var text = """
    Trip ID: T-116KYL6KW
    Total Rate: 2500.00
    Total Loaded Miles: 850 mi
    Pu-address: SWF2, Garner, NC
    Del-address: TOL3, Perrysburg, OH
    """

    RelayTextInputView(
        text: $text,
        parseMessage: "Parsed T-116KYL6KW",
        errorMessage: nil,
        onParse: {},
        onClear: {}
    )
    .padding()
    .forestBackground()
}
