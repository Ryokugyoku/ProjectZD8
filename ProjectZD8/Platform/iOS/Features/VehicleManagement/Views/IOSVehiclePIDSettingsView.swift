#if os(iOS)
import SwiftUI

/// iPhoneで1台の対応PID収集選択を編集します。
struct IOSVehiclePIDSettingsView: View {
    /// Applicationが提供する対応PID選択です。
    let items: [VehiclePIDSelectionItem]
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void

    /// 検索可能なPID選択一覧を提供します。
    ///
    /// 責務: 車両別対応PID設定をiPhone用の収集Toggle一覧へ変換します。
    var body: some View {
        NavigationStack {
            List(items) { item in
                Toggle(isOn: Binding(
                    get: { item.isEnabled },
                    set: { send(.pidCollectionChanged(item.id, $0)) }
                )) {
                    Text(item.nameKey.map { LocalizedStringKey($0) } ?? "garage.pid_settings.unconfirmed")
                    Text(String(format: "01 %02X", item.id.pid)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("garage.pid_settings.title")
            .overlay {
                if items.isEmpty { ContentUnavailableView("garage.pid_settings.empty", systemImage: "waveform.slash") }
            }
            .toolbar { Button("common.close") { send(.pidSettingsClosed) } }
        }
    }
}
#endif
