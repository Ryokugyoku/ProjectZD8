#if os(macOS)
import SwiftUI

/// 絞り込み結果が空であることを示す表示です。
struct MacOSConnectionHistoryVehicleSessionsNoResults: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 絞り込み0件の説明を描画します。
    ///
    /// 責務: 絞り込み結果0件を説明付きの空状態表示へ配置します。
    var body: some View {
        ContentUnavailableView("history.filter.empty", systemImage: "magnifyingglass", description: Text("history.filter.empty.body"))
            .frame(maxWidth: .infinity).padding(.vertical, 40 * scale)
    }
}
#endif
