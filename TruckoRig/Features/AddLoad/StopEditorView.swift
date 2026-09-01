import SwiftUI

/// Edits a single pickup or delivery.
struct StopEditorView: View {

    @Binding var stop: StopDraft
    @Environment(\.dismiss) private var dismiss

    @State private var hasSchedule: Bool
    @State private var scheduledTime: Date

    init(stop: Binding<StopDraft>) {
        _stop = stop
        _hasSchedule = State(initialValue: stop.wrappedValue.scheduledTime != nil)
        _scheduledTime = State(initialValue: stop.wrappedValue.scheduledTime ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("stop.type", selection: $stop.type) {
                        Text("stop.type.pickup").tag(StopType.pickup)
                        Text("stop.type.delivery").tag(StopType.delivery)
                    }
                    .pickerStyle(.segmented)
                }

                Section("stop.location") {
                    TextField("stop.facility", text: facilityBinding)
                        .textInputAutocapitalization(.characters)
                    TextField("stop.city", text: $stop.city)
                    TextField("stop.state", text: stateBinding)
                        .textInputAutocapitalization(.characters)
                    TextField("stop.zip", text: $stop.zip)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section("stop.schedule") {
                    Toggle("stop.hasSchedule", isOn: $hasSchedule)
                    if hasSchedule {
                        DatePicker("stop.scheduledTime", selection: $scheduledTime)
                    }
                }

                Section("stop.notes") {
                    TextField("stop.note", text: noteBinding, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(stop.type == .pickup ? "stop.type.pickup" : "stop.type.delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        apply()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
    }

    private func apply() {
        stop.state = USStates.normalize(stop.state)
        stop.scheduledTime = hasSchedule ? scheduledTime : nil
        // The raw Relay text no longer describes the appointment once it is edited by hand.
        if hasSchedule { stop.scheduledTimeRaw = "" }
        if stop.fullAddress.isEmpty { stop.fullAddress = stop.cityState }
    }

    private var facilityBinding: Binding<String> {
        Binding(get: { stop.facility ?? "" }, set: { stop.facility = $0.nonEmpty })
    }

    private var stateBinding: Binding<String> {
        Binding(get: { stop.state }, set: { stop.state = String($0.prefix(20)) })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { stop.note ?? "" }, set: { stop.note = $0.nonEmpty })
    }
}

/// Compact stop row used inside the add and edit forms.
struct StopRowView: View {
    let stop: StopDraft

    var body: some View {
        HStack(spacing: Spacing.tight) {
            Text(stop.type.shortLabel)
                .font(.appCaptionMedium)
                .foregroundStyle(stop.type == .pickup ? Color.forestPrimary : Color.forestAccent)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.cityState.isEmpty ? String(localized: "stop.unnamed") : stop.cityState)
                    .font(.appBody)
                    .foregroundStyle(Color.forestText)
                if let schedule = stop.scheduledTime {
                    Text(DateUtils.dateTime(schedule))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                } else if !stop.scheduledTimeRaw.isEmpty {
                    Text(stop.scheduledTimeRaw)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
            Spacer()
            if let facility = stop.facility {
                Text(facility)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var stop = StopDraft(
        type: .pickup,
        facility: "SWF2",
        city: "Garner",
        state: "NC",
        scheduledTime: Date()
    )

    return StopEditorView(stop: $stop)
}
