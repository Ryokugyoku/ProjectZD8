#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// iPhoneで車両別の軽整備と重整備を素早く記録・閲覧します。
struct IOSMaintenanceView: View {
    /// Maintenanceが提供する一覧と編集状態です。
    let state: MaintenanceState
    /// 画面操作をMaintenanceへ通知する処理です。
    let send: (MaintenanceAction) -> Void

    /// 編集中は専用フォーム、それ以外は車両別タイムラインを描画します。
    ///
    /// 責務: iPhone向け整備状態を一覧または編集レイアウトへ振り分けます。
    var body: some View {
        NavigationStack {
            Group {
                if let draft = state.draft {
                    IOSMaintenanceEditorView(draft: draft, failureKey: state.failureKey, send: send)
                } else {
                    timeline
                }
            }
            .navigationTitle("sidebar.maintenance")
        }
        .accessibilityIdentifier("ios-maintenance")
    }

    /// 車両選択、区分選択、記録カードを縦に並べる一覧です。
    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                vehiclePicker
                creationPanel
                syncBanner

                if state.visibleRecords.isEmpty {
                    ContentUnavailableView(
                        "maintenance.empty.title",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("maintenance.empty.message")
                    )
                } else {
                    ForEach(state.visibleRecords) { record in
                        recordCard(record)
                    }
                }
            }
            .padding(16)
        }
        .refreshable { send(.refreshRequested) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { send(.refreshRequested) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(state.phase == .syncing)
                    .accessibilityLabel(Text("maintenance.sync"))
            }
        }
    }

    /// 登録車両を必須選択するコントロールです。
    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("maintenance.vehicle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if state.vehicles.isEmpty {
                Label("maintenance.vehicle.empty", systemImage: "car.badge.questionmark")
                    .foregroundStyle(.secondary)
            } else {
                Picker("maintenance.vehicle", selection: vehicleSelection) {
                    ForEach(state.vehicles) { vehicle in
                        Text(vehicle.name.isEmpty ? vehicle.displayIdentifier : vehicle.name).tag(vehicle.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// 現在の車両選択を型付き操作へ変換するBindingです。
    private var vehicleSelection: Binding<VehicleID> {
        Binding(
            get: { state.selectedVehicleID ?? state.vehicles.first?.id ?? VehicleID() },
            set: { send(.vehicleSelected($0)) }
        )
    }

    /// 親指で軽整備と重整備を開始できる主要操作です。
    private var creationPanel: some View {
        HStack(spacing: 12) {
            createButton(kind: .light, symbol: "drop.fill", tint: .blue)
            createButton(kind: .heavy, symbol: "wrench.and.screwdriver.fill", tint: .orange)
        }
    }

    /// 1区分の新規記録ボタンを生成します。
    ///
    /// 責務: 1件の整備区分を大きな開始ボタンとして描画します。
    /// - Parameters:
    ///   - kind: 開始する整備区分。
    ///   - symbol: 区分を示すSF Symbol。
    ///   - tint: 区分のアクセント色。
    /// - Returns: 選択車両がある場合だけ有効なボタン。
    private func createButton(kind: MaintenanceKind, symbol: String, tint: Color) -> some View {
        Button { send(.createRequested(kind)) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title2)
                Text(LocalizedStringKey(kind.localizationKey)).font(.headline)
                Text(kind == .light ? "maintenance.kind.light.hint" : "maintenance.kind.heavy.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(16)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state.selectedVehicleID == nil)
    }

    /// 同期中または失敗状態を一覧上部へ表示します。
    @ViewBuilder
    private var syncBanner: some View {
        if state.phase == .syncing {
            Label("maintenance.syncing", systemImage: "icloud.and.arrow.up")
                .foregroundStyle(.secondary)
        } else if let failureKey = state.failureKey {
            Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        }
    }

    /// 保存済み整備1件の要約カードを生成します。
    ///
    /// 責務: 1件の整備記録を編集可能なタイムラインカードへ変換します。
    /// - Parameter record: 表示する車両別整備記録。
    /// - Returns: 区分、日時、作業数、写真数を示すカード。
    private func recordCard(_ record: MaintenanceRecord) -> some View {
        Button { send(.editRequested(record.id)) } label: {
            HStack(spacing: 14) {
                Image(systemName: record.kind == .light ? "drop.fill" : "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(record.kind == .light ? Color.blue : Color.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title).font(.headline).foregroundStyle(.primary)
                    Text(record.performedAt, format: .dateTime.year().month().day())
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(record.workItems.count) · \(record.photos.count)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios-maintenance-record-\(record.id.rawValue.uuidString)")
    }
}

/// iPhoneで整備内容、写真、締結証跡を編集します。
private struct IOSMaintenanceEditorView: View {
    /// 現在の未保存入力です。
    let draft: MaintenanceEditorDraft
    /// 直近の入力または保存失敗キーです。
    let failureKey: String?
    /// 編集操作をMaintenanceへ通知する処理です。
    let send: (MaintenanceAction) -> Void
    /// 画像ファイル選択を表示するかを示します。
    @State private var importsPhoto = false

    /// 基本情報、作業、写真、重整備証跡を1本のフォームへ描画します。
    ///
    /// 責務: iPhone向け未保存整備入力を操作可能なフォームとして表示します。
    var body: some View {
        Form {
            Section("maintenance.section.overview") {
                TextField("maintenance.field.title", text: binding(\.title))
                DatePicker("maintenance.field.performed_at", selection: binding(\.performedAt), displayedComponents: [.date, .hourAndMinute])
                TextField("maintenance.field.odometer", value: binding(\.odometerKilometers), format: .number)
                    .keyboardType(.decimalPad)
                TextField("maintenance.field.notes", text: binding(\.notes), axis: .vertical)
                    .lineLimit(4...10)
            }

            Section("maintenance.section.work_items") {
                ForEach(draft.workItems.indices, id: \.self) { index in
                    workItem(index)
                }
                Button("maintenance.add.work_item", systemImage: "plus") { send(.workItemAdded) }
            }

            Section("maintenance.section.photos") {
                photoGrid
                Button("maintenance.add.photo", systemImage: "photo.badge.plus") { importsPhoto = true }
            }

            if draft.kind == .heavy {
                Section("maintenance.section.fasteners") {
                    Text("maintenance.fastener.guidance").font(.caption).foregroundStyle(.secondary)
                    ForEach(draft.fastenerGroups.indices, id: \.self) { index in
                        fastenerGroup(index)
                    }
                    Button("maintenance.add.fastener_group", systemImage: "plus") { send(.fastenerGroupAdded) }
                }
            }

            if let failureKey {
                Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if let recordID = draft.recordID {
                Section {
                    Button("maintenance.delete", role: .destructive) { send(.deleteRequested(recordID)) }
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey(draft.kind.localizationKey)))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("maintenance.cancel") { send(.editingCancelled) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("maintenance.save") { send(.saveRequested) }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fileImporter(isPresented: $importsPhoto, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { send(.photoSelected(url)) }
        }
    }

    /// Draftプロパティの変更を型付き操作へ変換します。
    ///
    /// 責務: 1件の編集可能プロパティを全Draft更新操作へ接続します。
    /// - Parameter keyPath: 編集対象のDraft書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func binding<Value>(_ keyPath: WritableKeyPath<MaintenanceEditorDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: keyPath] }, set: { value in
            var changed = draft
            changed[keyPath: keyPath] = value
            send(.draftChanged(changed))
        })
    }

    /// 1件の部品作業入力を描画します。
    ///
    /// 責務: 指定位置の作業項目を部品、作業種別、製品仕様入力へ変換します。
    /// - Parameter index: Draft内の作業項目位置。
    /// - Returns: 作業項目編集View。
    private func workItem(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("maintenance.field.component", selection: workItemBinding(index, \.component)) {
                ForEach(MaintenanceComponent.allCases, id: \.self) { component in
                    Text(LocalizedStringKey(component.localizationKey)).tag(component)
                }
            }
            Picker("maintenance.field.operation", selection: workItemBinding(index, \.operation)) {
                ForEach(MaintenanceOperation.allCases, id: \.self) { operation in
                    Text(LocalizedStringKey(operation.localizationKey)).tag(operation)
                }
            }
            TextField("maintenance.field.part_name", text: workItemBinding(index, \.partName))
            TextField("maintenance.field.product_name", text: workItemBinding(index, \.productName))
            TextField("maintenance.field.manufacturer", text: workItemBinding(index, \.manufacturer))
            TextField("maintenance.field.specification", text: workItemBinding(index, \.specification))
            HStack {
                TextField("maintenance.field.quantity", value: workItemBinding(index, \.quantity), format: .number)
                TextField("maintenance.field.unit", text: workItemBinding(index, \.unit))
            }
            TextField("maintenance.field.item_notes", text: workItemBinding(index, \.notes), axis: .vertical)
            Button("maintenance.remove", role: .destructive) { send(.workItemRemoved(draft.workItems[index].id)) }
        }
        .padding(.vertical, 6)
    }

    /// 作業項目プロパティの変更をDraft更新へ接続します。
    ///
    /// 責務: 指定作業項目の1プロパティを全Draft更新操作へ変換します。
    /// - Parameters:
    ///   - index: Draft内の作業項目位置。
    ///   - keyPath: 作業項目内の書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func workItemBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<MaintenanceWorkItem, Value>) -> Binding<Value> {
        Binding(get: { draft.workItems[index][keyPath: keyPath] }, set: { value in
            var changed = draft
            changed.workItems[index][keyPath: keyPath] = value
            send(.draftChanged(changed))
        })
    }

    /// 添付済み写真をスクロール可能なサムネイルとして描画します。
    private var photoGrid: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(draft.photos) { photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image)
                            .resizable().scaledToFill().frame(width: 112, height: 84).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Button { send(.photoRemoved(photo.id)) } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain).padding(5)
                            }
                    }
                }
            }
        }
    }

    /// 1件の締結グループと個別トルク証跡を描画します。
    ///
    /// 責務: 指定位置の分解本数と全個別締結入力を追跡可能なフォームへ変換します。
    /// - Parameter index: Draft内の締結グループ位置。
    /// - Returns: 分解・締結証跡編集View。
    private func fastenerGroup(_ index: Int) -> some View {
        let group = draft.fastenerGroups[index]
        return VStack(alignment: .leading, spacing: 10) {
            TextField("maintenance.field.fastener_group", text: fastenerGroupBinding(index, \.name))
            TextField("maintenance.field.location", text: fastenerGroupBinding(index, \.location))
            HStack {
                TextField("maintenance.field.expected_count", value: fastenerGroupBinding(index, \.expectedCount), format: .number)
                TextField("maintenance.field.removed_count", value: fastenerGroupBinding(index, \.removedCount), format: .number)
            }
            TextField("maintenance.field.removal_notes", text: fastenerGroupBinding(index, \.removalNotes), axis: .vertical)
            ForEach(group.installations.indices, id: \.self) { evidenceIndex in
                fastenerEvidence(groupIndex: index, evidenceIndex: evidenceIndex)
            }
            Button("maintenance.add.fastener", systemImage: "plus") { send(.fastenerAdded(group.id)) }
            Button("maintenance.remove.group", role: .destructive) { send(.fastenerGroupRemoved(group.id)) }
        }
        .padding(.vertical, 8)
    }

    /// 締結グループプロパティをDraft更新へ接続します。
    ///
    /// 責務: 指定締結グループの1プロパティを全Draft更新操作へ変換します。
    /// - Parameters:
    ///   - index: Draft内の締結グループ位置。
    ///   - keyPath: 締結グループ内の書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func fastenerGroupBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<MaintenanceFastenerGroup, Value>) -> Binding<Value> {
        Binding(get: { draft.fastenerGroups[index][keyPath: keyPath] }, set: { value in
            var changed = draft
            changed.fastenerGroups[index][keyPath: keyPath] = value
            send(.draftChanged(changed))
        })
    }

    /// 1本分の位置、トルク、工具、担当者、写真証跡を描画します。
    ///
    /// 責務: 指定した個別締結証跡を確定操作付き入力へ変換します。
    /// - Parameters:
    ///   - groupIndex: Draft内の締結グループ位置。
    ///   - evidenceIndex: グループ内の個別証跡位置。
    /// - Returns: 個別締結証跡編集View。
    private func fastenerEvidence(groupIndex: Int, evidenceIndex: Int) -> some View {
        let group = draft.fastenerGroups[groupIndex]
        let evidence = group.installations[evidenceIndex]
        return VStack(alignment: .leading, spacing: 8) {
            TextField("maintenance.field.fastener_position", text: evidenceBinding(groupIndex, evidenceIndex, \.position))
            TextField("maintenance.field.torque", value: evidenceBinding(groupIndex, evidenceIndex, \.torqueNewtonMeters), format: .number)
            TextField("maintenance.field.tool", text: evidenceBinding(groupIndex, evidenceIndex, \.tool))
            TextField("maintenance.field.technician", text: evidenceBinding(groupIndex, evidenceIndex, \.tightenedBy))
            HStack {
                Button("maintenance.fastener.confirm") { send(.fastenerConfirmed(group.id, evidence.id)) }
                if !draft.photos.isEmpty {
                    Button("maintenance.fastener.link_photo") { send(.latestPhotoLinked(group.id, evidence.id)) }
                }
            }
            if let tightenedAt = evidence.tightenedAt {
                Text(tightenedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 個別締結プロパティをDraft更新へ接続します。
    ///
    /// 責務: 指定した1本の締結プロパティを全Draft更新操作へ変換します。
    /// - Parameters:
    ///   - groupIndex: Draft内の締結グループ位置。
    ///   - evidenceIndex: グループ内の個別証跡位置。
    ///   - keyPath: 個別締結内の書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func evidenceBinding<Value>(
        _ groupIndex: Int,
        _ evidenceIndex: Int,
        _ keyPath: WritableKeyPath<FastenerInstallationEvidence, Value>
    ) -> Binding<Value> {
        Binding(get: { draft.fastenerGroups[groupIndex].installations[evidenceIndex][keyPath: keyPath] }, set: { value in
            var changed = draft
            changed.fastenerGroups[groupIndex].installations[evidenceIndex][keyPath: keyPath] = value
            send(.draftChanged(changed))
        })
    }
}
#endif
