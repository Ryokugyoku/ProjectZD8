#if os(macOS)
import SwiftUI

/// 整備エディタの作業項目セクション(部位・作業・製品・数量など)。
struct MacOSMaintenanceWorkItemsSection: View {
    let draft: MaintenanceDraft
    let send: (MaintenanceAction) -> Void

    var body: some View {
        Section {
            ForEach(draft.workItems) { item in
                VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                    HStack {
                        Picker(selection: binding(item, \.component)) {
                            ForEach(MaintenanceComponent.allCases, id: \.self) { component in
                                Text(LocalizedStringKey(component.localizationKey)).tag(component)
                            }
                        } label: {
                            Text("maintenance.work.component")
                        }
                        Picker(selection: binding(item, \.operation)) {
                            ForEach(MaintenanceOperation.allCases, id: \.self) { operation in
                                Text(LocalizedStringKey(operation.localizationKey)).tag(operation)
                            }
                        } label: {
                            Text("maintenance.work.operation")
                        }
                        Button(role: .destructive) {
                            send(.workItemRemoved(item.id))
                        } label: {
                            Label("maintenance.work.remove", systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                    TextField(text: binding(item, \.partName)) { Text("maintenance.work.partName") }
                    TextField(text: binding(item, \.productName)) { Text("maintenance.work.productName") }
                    TextField(text: binding(item, \.manufacturer)) { Text("maintenance.work.manufacturer") }
                    TextField(text: binding(item, \.specification)) { Text("maintenance.work.specification") }
                    HStack {
                        TextField(value: binding(item, \.quantity), format: .number) { Text("maintenance.work.quantity") }
                        TextField(text: binding(item, \.unit)) { Text("maintenance.work.unit") }
                    }
                    TextField(text: binding(item, \.notes), axis: .vertical) { Text("maintenance.work.notes") }
                        .lineLimit(1...4)
                }
                .padding(.vertical, InsightSpacing.xs)
                Divider()
            }
            Button {
                send(.workItemAdded)
            } label: {
                Label("maintenance.work.add", systemImage: "plus")
            }
        } header: {
            Text("maintenance.section.work")
        }
    }

    /// 責務: 作業項目の1フィールドを、下書き全体の差し替え Action に変換する Binding を作る。
    private func binding<Value>(_ item: MaintenanceWorkItem, _ keyPath: WritableKeyPath<MaintenanceWorkItem, Value>) -> Binding<Value> {
        Binding(
            get: { draft.workItems.first { $0.id == item.id }?[keyPath: keyPath] ?? item[keyPath: keyPath] },
            set: { value in
                var next = draft
                guard let index = next.workItems.firstIndex(where: { $0.id == item.id }) else { return }
                next.workItems[index][keyPath: keyPath] = value
                send(.draftChanged(next))
            }
        )
    }
}
#endif
