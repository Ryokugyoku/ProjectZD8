#if os(iOS)
import SwiftUI

/// 整備の基本情報(区分・表題・実施日・走行距離・メモ)の入力セクションです。
struct IOSMaintenanceBasicsSection: View {
    @Binding var draft: MaintenanceDraft

    var body: some View {
        Section {
            LabeledContent("maintenance.field.kind") {
                Text(LocalizedStringKey(draft.kind.localizationKey)).foregroundStyle(.secondary)
            }
            TextField("maintenance.field.title", text: $draft.title)
            DatePicker("maintenance.field.performedAt", selection: $draft.performedAt)
            TextField("maintenance.field.odometer", value: $draft.odometerKilometers, format: .number)
                .keyboardType(.decimalPad)
            TextField("maintenance.field.notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...8)
        } header: {
            Text("maintenance.editor.basics")
        } footer: {
            Text(LocalizedStringKey(draft.kind.hintLocalizationKey))
        }
    }
}
#endif
