#if os(macOS)
import SwiftUI

/// 任意の日付条件を有効化チェックと日付選択で指定する操作です。
struct MacOSConnectionHistoryVehicleSessionsDateFilter: View {
    /// 日付条件のローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 現在選択中の日付です。未指定は `nil`。
    let date: Date?
    /// 有効化時に使う履歴由来の初期日です。
    let fallback: Date
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 変更後の日付の通知先です。
    let update: (Date?) -> Void

    /// 有効化チェックと、有効時だけ日付選択欄を描画します。
    ///
    /// 責務: 1件の任意日付を有効化操作と日付選択操作へ配置します。
    var body: some View {
        HStack(spacing: 7 * scale) {
            Toggle(titleKey, isOn: Binding(get: { date != nil }, set: { update($0 ? fallback : nil) })).toggleStyle(.checkbox)
            if let date {
                DatePicker("", selection: Binding(get: { date }, set: { update($0) }), displayedComponents: .date).labelsHidden()
            }
        }
    }
}
#endif
