import SwiftUI

/// Equipment and deadhead miles. Driven miles are loaded miles plus deadhead, as on Android.
struct LoadExtraFields: View {
    @Binding var draft: LoadDraft

    var body: some View {
        Section("load.equipment") {
            Picker("load.equipment", selection: equipmentBinding) {
                Text("load.equipment.none").tag("")
                ForEach(EquipmentType.allCases) { type in
                    Text(title(type)).tag(type.rawValue)
                }
            }
            SoftNumberField(title: "load.deadhead", value: $draft.deadheadMiles)
            LabeledContent("stat.miles") {
                Text(Formatters.miles(draft.drivenMiles))
            }
        }
    }

    private var equipmentBinding: Binding<String> {
        Binding(
            get: { draft.equipmentType ?? "" },
            set: { draft.equipmentType = $0.isEmpty ? nil : $0 }
        )
    }

    private func title(_ type: EquipmentType) -> LocalizedStringKey {
        switch type {
        case .dryVan: return "load.equipment.dryVan"
        case .reefer: return "load.equipment.reefer"
        case .flatbed: return "load.equipment.flatbed"
        case .powerOnly: return "load.equipment.powerOnly"
        case .amazonRelay: return "load.equipment.amazonRelay"
        case .boxTruck: return "load.equipment.boxTruck"
        case .cargoVan: return "load.equipment.cargoVan"
        case .other: return "load.equipment.other"
        }
    }
}
