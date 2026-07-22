#if os(iOS)
import SwiftUI

/// iPhoneで1台の対応PIDを検索と状態条件で絞り込みます。
struct IOSVehiclePIDSettingsView: View {
    /// Applicationが提供する対応PID選択です。
    let items: [VehiclePIDSelectionItem]
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void
    /// 名称またはService/PIDを探す検索文字列です。
    @State private var query = ""
    /// 一覧へ適用する収集状態条件です。
    @State private var filter: IOSPIDCollectionFilter = .all

    /// 件数概要、状態条件、検索を備えたPID選択一覧を提供します。
    ///
    /// 責務: 車両別対応PID設定をiPhone用の絞り込み可能な収集Toggle一覧へ変換します。
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("garage.pid_settings.filter", selection: $filter) {
                        ForEach(IOSPIDCollectionFilter.allCases) { filter in
                            Text(filter.titleKey).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("garage.pid_settings.summary \(enabledCount) \(items.count)")
                }

                Section("garage.pid_settings.results") {
                    ForEach(filteredItems) { item in
                        Toggle(isOn: Binding(
                            get: { item.isEnabled },
                            set: { send(.pidCollectionChanged(item.id, $0)) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.nameKey.map { LocalizedStringKey($0) } ?? "garage.pid_settings.unconfirmed")
                                    .font(.body.weight(.medium))
                                HStack(spacing: 7) {
                                    Text(servicePIDText(item.id))
                                        .font(.caption.monospaced().weight(.semibold))
                                    Text(item.isEnabled ? "garage.pid_settings.collecting" : "garage.pid_settings.paused")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(item.isEnabled ? Color.green : Color.secondary)
                                    if let modelCode = item.vehicleModelCode {
                                        VehicleModelBadge(modelCode: modelCode)
                                            .scaleEffect(0.72)
                                            .frame(width: 28, height: 28)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("ios-pid-\(item.id.service)-\(item.id.pid)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("garage.pid_settings.title")
            .searchable(text: $query, prompt: "garage.pid_settings.search")
            .overlay {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "garage.pid_settings.empty" : "garage.pid_settings.no_results",
                        systemImage: query.isEmpty ? "waveform.slash" : "magnifyingglass"
                    )
                }
            }
            .toolbar { Button("common.close") { send(.pidSettingsClosed) } }
        }
    }

    /// 収集有効な対応PID件数です。
    private var enabledCount: Int { items.lazy.filter(\.isEnabled).count }

    /// 検索文字列と収集状態条件を同時に満たすPIDです。
    private var filteredItems: [VehiclePIDSelectionItem] {
        items.filter { item in
            filter.matches(item) && matchesQuery(item)
        }
    }

    /// 1件のPIDが現在の検索文字列へ一致するかを返します。
    ///
    /// 責務: PID名称、Service/PID表記、16進PID番号を単一検索文字列で照合します。
    /// - Parameter item: 照合する対応PID選択。
    /// - Returns: 検索対象へ含める場合は `true`。
    private func matchesQuery(_ item: VehiclePIDSelectionItem) -> Bool {
        guard !query.isEmpty else { return true }
        let localizedName = item.nameKey.map { String(localized: String.LocalizationValue($0)) } ?? ""
        return localizedName.localizedCaseInsensitiveContains(query)
            || servicePIDText(item.id).localizedCaseInsensitiveContains(query)
            || String(format: "%02X", item.id.pid).localizedCaseInsensitiveContains(query)
    }

    /// ServiceとPIDを固定幅16進表記へ変換します。
    ///
    /// 責務: 1件のOBD読取要求をユーザーが検索・識別できる標準表示へ変換します。
    /// - Parameter request: 表示するService/PID要求。
    /// - Returns: `MODE 01 · PID 0C` 形式の文字列。
    private func servicePIDText(_ request: OBDPIDRequest) -> String {
        String(format: "MODE %02X · PID %02X", request.service, request.pid)
    }
}

/// iPhoneの対応PID一覧へ適用する収集状態条件です。
private enum IOSPIDCollectionFilter: String, CaseIterable, Identifiable {
    /// 全対応PIDを表示します。
    case all
    /// 収集中のPIDだけを表示します。
    case enabled
    /// 一時停止中のPIDだけを表示します。
    case disabled

    /// Picker用の安定識別子です。
    var id: String { rawValue }

    /// 条件名のローカライズキーです。
    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "garage.pid_settings.filter.all"
        case .enabled: "garage.pid_settings.filter.enabled"
        case .disabled: "garage.pid_settings.filter.disabled"
        }
    }

    /// 1件のPID選択が条件へ一致するかを返します。
    ///
    /// 責務: 1件の収集状態を選択中の単一条件で判定します。
    /// - Parameter item: 判定するPID選択。
    /// - Returns: 一覧へ含める場合は `true`。
    func matches(_ item: VehiclePIDSelectionItem) -> Bool {
        switch self {
        case .all: true
        case .enabled: item.isEnabled
        case .disabled: !item.isEnabled
        }
    }
}
#endif
