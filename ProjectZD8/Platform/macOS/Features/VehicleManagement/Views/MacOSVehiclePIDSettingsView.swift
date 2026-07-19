#if os(macOS)
import SwiftUI

/// macOSで1台の対応PID収集選択を編集します。
struct MacOSVehiclePIDSettingsView: View {
    /// Applicationが提供する対応PID選択です。
    let items: [VehiclePIDSelectionItem]
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void
    /// 長い対応一覧を絞り込む検索文字列です。
    @State private var query = ""

    /// 検索と全件スクロールに対応するPID選択一覧を提供します。
    ///
    /// 責務: 車両別対応PID設定をmacOS用の検索可能な収集Toggle一覧へ変換します。
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("garage.pid_settings.title").font(.title2.bold())
                Spacer()
                Button("common.close") { send(.pidSettingsClosed) }
            }.padding()
            List(filteredItems) { item in
                Toggle(isOn: Binding(
                    get: { item.isEnabled },
                    set: { send(.pidCollectionChanged(item.id, $0)) }
                )) {
                    HStack {
                        Text(item.nameKey.map { LocalizedStringKey($0) } ?? "garage.pid_settings.unconfirmed")
                        Spacer()
                        Text(String(format: "01 %02X", item.id.pid)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "garage.pid_settings.search")
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    /// 検索文字列に一致するPID設定です。
    private var filteredItems: [VehiclePIDSelectionItem] {
        guard !query.isEmpty else { return items }
        return items.filter { String(format: "%02X", $0.id.pid).localizedCaseInsensitiveContains(query) }
    }
}
#endif
