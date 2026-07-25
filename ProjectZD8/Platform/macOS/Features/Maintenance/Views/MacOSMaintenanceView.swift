#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// macOSで車両別整備履歴と専門的な作業証跡を一覧・編集します。
struct MacOSMaintenanceView: View {
    /// Maintenanceが提供する一覧と編集状態です。
    let state: MaintenanceState
    /// 画面操作をMaintenanceへ通知する処理です。
    let send: (MaintenanceAction) -> Void
    /// 現在のウインドウに対応するAppShell寸法です。
    let metrics: MacOSAppShellMetrics

    /// 車両別一覧と詳細編集を同時に確認できる2ペイン画面です。
    ///
    /// 責務: macOS向け整備状態を車両タイムラインと専門編集ペインへ描画します。
    var body: some View {
        HStack(spacing: 0) {
            timeline
                .frame(minWidth: 260 * metrics.scale, idealWidth: 330 * metrics.scale, maxWidth: 390 * metrics.scale)
            Divider()
            if let draft = state.draft {
                MacOSMaintenanceEditorView(draft: draft, failureKey: state.failureKey, send: send, metrics: metrics)
            } else {
                overview
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("macos-maintenance")
    }

    /// 車両選択、絞り込み、記録一覧をまとめる左ペインです。
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("sidebar.maintenance")
                        .font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded))
                    Text("maintenance.subtitle")
                        .font(.system(size: 12 * metrics.scale)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { send(.refreshRequested) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(state.phase == .syncing)
                    .help("maintenance.sync")
            }

            if state.vehicles.isEmpty {
                Label("maintenance.vehicle.empty", systemImage: "car.badge.questionmark")
                    .foregroundStyle(.secondary)
            } else {
                Picker("maintenance.vehicle", selection: vehicleSelection) {
                    ForEach(state.vehicles) { vehicle in
                        Text(vehicle.name.isEmpty ? vehicle.displayIdentifier : vehicle.name).tag(vehicle.id)
                    }
                }
            }

            Picker("maintenance.filter", selection: kindSelection) {
                Text("maintenance.filter.all").tag(MaintenanceKind?.none)
                ForEach(MaintenanceKind.allCases, id: \.self) { kind in
                    Text(LocalizedStringKey(kind.localizationKey)).tag(Optional(kind))
                }
            }
            .pickerStyle(.segmented)

            if state.phase == .syncing {
                HStack { ProgressView().controlSize(.small); Text("maintenance.syncing") }
                    .font(.caption).foregroundStyle(.secondary)
            } else if let failureKey = state.failureKey {
                Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.icloud")
                    .font(.caption).foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(spacing: 9 * metrics.scale) {
                    ForEach(state.visibleRecords) { record in
                        recordRow(record)
                    }
                    if state.visibleRecords.isEmpty {
                        ContentUnavailableView("maintenance.empty.title", systemImage: "wrench.and.screwdriver")
                            .padding(.top, 30)
                    }
                }
            }
        }
        .padding(20 * metrics.scale)
        .background(.ultraThinMaterial)
    }

    /// 現在の車両選択をMaintenance操作へ接続します。
    private var vehicleSelection: Binding<VehicleID> {
        Binding(
            get: { state.selectedVehicleID ?? state.vehicles.first?.id ?? VehicleID() },
            set: { send(.vehicleSelected($0)) }
        )
    }

    /// 現在の区分絞り込みをMaintenance操作へ接続します。
    private var kindSelection: Binding<MaintenanceKind?> {
        Binding(get: { state.kindFilter }, set: { send(.kindFilterChanged($0)) })
    }

    /// 記録未選択時に新規作成と同期概要を示す右ペインです。
    private var overview: some View {
        VStack(alignment: .leading, spacing: 24 * metrics.scale) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 54 * metrics.scale, weight: .medium))
                .foregroundStyle(.tint)
            Text("maintenance.overview.title")
                .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
            Text("maintenance.overview.message")
                .font(.system(size: 15 * metrics.scale)).foregroundStyle(.secondary)
                .frame(maxWidth: 580 * metrics.scale, alignment: .leading)
            HStack(spacing: 14 * metrics.scale) {
                createButton(kind: .light, symbol: "drop.fill", tint: .blue)
                createButton(kind: .heavy, symbol: "wrench.and.screwdriver.fill", tint: .orange)
            }
            if let date = state.lastSynchronizedAt {
                Label {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                } icon: { Image(systemName: "checkmark.icloud.fill") }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(42 * metrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 1区分の新規記録カードを生成します。
    ///
    /// 責務: 1件の整備区分を説明付きmacOS開始ボタンへ変換します。
    /// - Parameters:
    ///   - kind: 開始する整備区分。
    ///   - symbol: 区分を示すSF Symbol。
    ///   - tint: 区分のアクセント色。
    /// - Returns: 選択車両がある場合だけ有効な開始ボタン。
    private func createButton(kind: MaintenanceKind, symbol: String, tint: Color) -> some View {
        Button { send(.createRequested(kind)) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(kind.localizationKey)).font(.headline)
                    Text(LocalizedStringKey(kind == .light ? "maintenance.kind.light.hint" : "maintenance.kind.heavy.hint"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18).frame(maxWidth: 270 * metrics.scale, alignment: .leading)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state.selectedVehicleID == nil)
    }

    /// 保存済み記録を編集可能な一覧行へ変換します。
    ///
    /// 責務: 1件の整備記録を区分、日付、証跡数付き選択行として描画します。
    /// - Parameter record: 表示する車両別整備記録。
    /// - Returns: 編集開始操作を持つ一覧行。
    private func recordRow(_ record: MaintenanceRecord) -> some View {
        Button { send(.editRequested(record.id)) } label: {
            HStack(spacing: 11) {
                Image(systemName: record.kind == .light ? "drop.fill" : "wrench.and.screwdriver.fill")
                    .foregroundStyle(record.kind == .light ? Color.blue : Color.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title).font(.headline).lineLimit(1)
                    Text(record.performedAt, format: .dateTime.year().month().day())
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(record.workItems.count) · \(record.photos.count)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("macos-maintenance-record-\(record.id.rawValue.uuidString)")
    }
}

/// macOSで部品作業、写真、分解、締結トルクを詳細編集します。
private struct MacOSMaintenanceEditorView: View {
    /// 現在の未保存入力です。
    let draft: MaintenanceEditorDraft
    /// 直近の入力または保存失敗キーです。
    let failureKey: String?
    /// 編集操作をMaintenanceへ通知する処理です。
    let send: (MaintenanceAction) -> Void
    /// 現在のウインドウに対応するAppShell寸法です。
    let metrics: MacOSAppShellMetrics
    /// 写真ファイル選択を表示するかを示します。
    @State private var importsPhoto = false

    /// 専門作業者向けの全整備入力をスクロール可能な詳細ペインへ描画します。
    ///
    /// 責務: macOS向け未保存整備入力を分野別の専門編集フォームとして表示します。
    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22 * metrics.scale) {
                    overviewSection
                    workItemsSection
                    photosSection
                    if draft.kind == .heavy { fastenersSection }
                    if let failureKey {
                        Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(28 * metrics.scale)
                .frame(maxWidth: 900 * metrics.scale, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 編集中区分と保存・取消操作を表示する上部バーです。
    private var editorToolbar: some View {
        HStack {
            Image(systemName: draft.kind == .light ? "drop.fill" : "wrench.and.screwdriver.fill")
                .foregroundStyle(draft.kind == .light ? Color.blue : Color.orange)
            Text(LocalizedStringKey(draft.kind.localizationKey))
                .font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
            Spacer()
            if let recordID = draft.recordID {
                Button(role: .destructive) { send(.deleteRequested(recordID)) } label: { Image(systemName: "trash") }
                    .help("maintenance.delete")
            }
            Button("maintenance.cancel") { send(.editingCancelled) }
            Button("maintenance.save") { send(.saveRequested) }
                .buttonStyle(.borderedProminent)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24 * metrics.scale)
        .frame(height: 64 * metrics.scale)
    }

    /// 日時、距離、表題、全体記録を編集する領域です。
    private var overviewSection: some View {
        GroupBox("maintenance.section.overview") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow { Text("maintenance.field.title"); TextField("maintenance.field.title", text: binding(\.title)) }
                GridRow { Text("maintenance.field.performed_at"); DatePicker("", selection: binding(\.performedAt)) }
                GridRow { Text("maintenance.field.odometer"); TextField("maintenance.field.odometer", value: binding(\.odometerKilometers), format: .number) }
                GridRow { Text("maintenance.field.notes"); TextField("maintenance.field.notes", text: binding(\.notes), axis: .vertical).lineLimit(4...12) }
            }
            .padding(12)
        }
    }

    /// 部品と作業内容を任意件数編集する領域です。
    private var workItemsSection: some View {
        GroupBox("maintenance.section.work_items") {
            VStack(spacing: 14) {
                ForEach(draft.workItems.indices, id: \.self) { index in workItem(index) }
                Button("maintenance.add.work_item", systemImage: "plus") { send(.workItemAdded) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }

    /// 1件の部品作業を多列編集カードとして描画します。
    ///
    /// 責務: 指定位置の作業項目を部品、種別、製品仕様、数量入力へ変換します。
    /// - Parameter index: Draft内の作業項目位置。
    /// - Returns: macOS向け作業項目カード。
    private func workItem(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("maintenance.field.component", selection: workItemBinding(index, \.component)) {
                    ForEach(MaintenanceComponent.allCases, id: \.self) { Text(LocalizedStringKey($0.localizationKey)).tag($0) }
                }
                Picker("maintenance.field.operation", selection: workItemBinding(index, \.operation)) {
                    ForEach(MaintenanceOperation.allCases, id: \.self) { Text(LocalizedStringKey($0.localizationKey)).tag($0) }
                }
                Button(role: .destructive) { send(.workItemRemoved(draft.workItems[index].id)) } label: { Image(systemName: "trash") }
            }
            HStack {
                TextField("maintenance.field.part_name", text: workItemBinding(index, \.partName))
                TextField("maintenance.field.product_name", text: workItemBinding(index, \.productName))
                TextField("maintenance.field.manufacturer", text: workItemBinding(index, \.manufacturer))
            }
            HStack {
                TextField("maintenance.field.specification", text: workItemBinding(index, \.specification))
                TextField("maintenance.field.quantity", value: workItemBinding(index, \.quantity), format: .number).frame(width: 110)
                TextField("maintenance.field.unit", text: workItemBinding(index, \.unit)).frame(width: 100)
            }
            TextField("maintenance.field.item_notes", text: workItemBinding(index, \.notes), axis: .vertical)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 写真追加とサムネイル確認を提供する領域です。
    private var photosSection: some View {
        GroupBox("maintenance.section.photos") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                    ForEach(draft.photos) { photo in
                        if let image = NSImage(data: photo.data) {
                            Image(nsImage: image).resizable().scaledToFill().frame(height: 105).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button { send(.photoRemoved(photo.id)) } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain).padding(6)
                                }
                        }
                    }
                }
                Button("maintenance.add.photo", systemImage: "photo.badge.plus") { importsPhoto = true }
            }
            .padding(12)
        }
        .fileImporter(isPresented: $importsPhoto, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { send(.photoSelected(url)) }
        }
    }

    /// オーバーホールの分解本数と締結トルクを編集する領域です。
    private var fastenersSection: some View {
        GroupBox("maintenance.section.fasteners") {
            VStack(alignment: .leading, spacing: 14) {
                Text("maintenance.fastener.guidance").font(.caption).foregroundStyle(.secondary)
                ForEach(draft.fastenerGroups.indices, id: \.self) { index in fastenerGroup(index) }
                Button("maintenance.add.fastener_group", systemImage: "plus") { send(.fastenerGroupAdded) }
            }
            .padding(12)
        }
    }

    /// 1か所の分解本数と全個別締結証跡を描画します。
    ///
    /// 責務: 指定締結グループを可変本数の専門記録カードへ変換します。
    /// - Parameter index: Draft内の締結グループ位置。
    /// - Returns: macOS向け分解・締結編集カード。
    private func fastenerGroup(_ index: Int) -> some View {
        let group = draft.fastenerGroups[index]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("maintenance.field.fastener_group", text: groupBinding(index, \.name))
                TextField("maintenance.field.location", text: groupBinding(index, \.location))
                TextField("maintenance.field.expected_count", value: groupBinding(index, \.expectedCount), format: .number).frame(width: 120)
                TextField("maintenance.field.removed_count", value: groupBinding(index, \.removedCount), format: .number).frame(width: 120)
                Button(role: .destructive) { send(.fastenerGroupRemoved(group.id)) } label: { Image(systemName: "trash") }
            }
            TextField("maintenance.field.removal_notes", text: groupBinding(index, \.removalNotes), axis: .vertical)
            ForEach(group.installations.indices, id: \.self) { evidenceIndex in
                fastenerEvidence(groupIndex: index, evidenceIndex: evidenceIndex)
            }
            Button("maintenance.add.fastener", systemImage: "plus") { send(.fastenerAdded(group.id)) }
        }
        .padding(14)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 1本分の締結位置、実測トルク、工具、担当者、写真リンクを描画します。
    ///
    /// 責務: 指定個別締結を完了日時付き証跡入力行へ変換します。
    /// - Parameters:
    ///   - groupIndex: Draft内の締結グループ位置。
    ///   - evidenceIndex: グループ内の個別証跡位置。
    /// - Returns: macOS向け個別締結入力行。
    private func fastenerEvidence(groupIndex: Int, evidenceIndex: Int) -> some View {
        let group = draft.fastenerGroups[groupIndex]
        let evidence = group.installations[evidenceIndex]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("maintenance.field.fastener_position", text: evidenceBinding(groupIndex, evidenceIndex, \.position))
                TextField("maintenance.field.torque", value: evidenceBinding(groupIndex, evidenceIndex, \.torqueNewtonMeters), format: .number).frame(width: 130)
                TextField("maintenance.field.tool", text: evidenceBinding(groupIndex, evidenceIndex, \.tool))
                TextField("maintenance.field.technician", text: evidenceBinding(groupIndex, evidenceIndex, \.tightenedBy))
            }
            HStack {
                Button("maintenance.fastener.confirm") { send(.fastenerConfirmed(group.id, evidence.id)) }
                if !draft.photos.isEmpty {
                    Button("maintenance.fastener.link_photo") { send(.latestPhotoLinked(group.id, evidence.id)) }
                }
                if let date = evidence.tightenedAt {
                    Label { Text(date, format: .dateTime.year().month().day().hour().minute()) } icon: { Image(systemName: "checkmark.seal.fill") }
                        .foregroundStyle(.green)
                }
                if !evidence.photoIDs.isEmpty {
                    Label("\(evidence.photoIDs.count)", systemImage: "photo.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Draftプロパティの変更を型付き操作へ接続します。
    ///
    /// 責務: 1件のDraftプロパティを全Draft更新操作へ変換します。
    /// - Parameter keyPath: Draft内の書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func binding<Value>(_ keyPath: WritableKeyPath<MaintenanceEditorDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: keyPath] }, set: { value in
            var changed = draft; changed[keyPath: keyPath] = value; send(.draftChanged(changed))
        })
    }

    /// 作業項目プロパティの変更を型付き操作へ接続します。
    ///
    /// 責務: 指定作業項目の1プロパティを全Draft更新操作へ変換します。
    /// - Parameters:
    ///   - index: Draft内の作業項目位置。
    ///   - keyPath: 作業項目内の書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func workItemBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<MaintenanceWorkItem, Value>) -> Binding<Value> {
        Binding(get: { draft.workItems[index][keyPath: keyPath] }, set: { value in
            var changed = draft; changed.workItems[index][keyPath: keyPath] = value; send(.draftChanged(changed))
        })
    }

    /// 締結グループプロパティの変更を型付き操作へ接続します。
    ///
    /// 責務: 指定締結グループの1プロパティを全Draft更新操作へ変換します。
    /// - Parameters:
    ///   - index: Draft内の締結グループ位置。
    ///   - keyPath: 締結グループ内の書込可能KeyPath。
    /// - Returns: SwiftUI入力へ渡すBinding。
    private func groupBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<MaintenanceFastenerGroup, Value>) -> Binding<Value> {
        Binding(get: { draft.fastenerGroups[index][keyPath: keyPath] }, set: { value in
            var changed = draft; changed.fastenerGroups[index][keyPath: keyPath] = value; send(.draftChanged(changed))
        })
    }

    /// 個別締結プロパティの変更を型付き操作へ接続します。
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
