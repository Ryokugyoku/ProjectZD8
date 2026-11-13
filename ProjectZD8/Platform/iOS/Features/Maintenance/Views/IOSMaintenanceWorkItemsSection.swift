#if os(iOS)
import SwiftUI

/// 作業項目(部品・作業種別・製品情報)の入力セクションです。
struct IOSMaintenanceWorkItemsSection: View {
    @Binding var draft: MaintenanceDraft
    let send: (MaintenanceAction) -> Void

    var body: some View {
        ForEach($draft.workItems) { $item in
            Section {
                Picker("maintenance.field.component", selection: $item.component) {
                    ForEach(MaintenanceComponent.allCases, id: \.self) { component in
                        Text(LocalizedStringKey(component.localizationKey)).tag(component)
                    }
                }
                Picker("maintenance.field.operation", selection: $item.operation) {
                    ForEach(MaintenanceOperation.allCases, id: \.self) { operation in
                        Text(LocalizedStringKey(operation.localizationKey)).tag(operation)
                    }
                }
                TextField("maintenance.field.partName", text: $item.partName)
                TextField("maintenance.field.productName", text: $item.productName)
                TextField("maintenance.field.manufacturer", text: $item.manufacturer)
                TextField("maintenance.field.specification", text: $item.specification)
                HStack {
                    TextField("maintenance.field.quantity", value: $item.quantity, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("maintenance.field.unit", text: $item.unit)
                }
                TextField("maintenance.field.workNotes", text: $item.notes, axis: .vertical)
                    .lineLimit(1...6)
                Button("maintenance.workItem.remove", role: .destructive) { send(.workItemRemoved(item.id)) }
            } header: {
                Text("maintenance.editor.workItem")
            }
        }
        Section {
            Button { send(.workItemAdded) } label: {
                Label("maintenance.workItem.add", systemImage: "plus.circle")
            }
        }
    }
}
#endif
