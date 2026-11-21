#if os(iOS)
import SwiftUI

/// 絞り込み結果が空であることを示す表示です。
struct IOSConnectionHistoryVehicleSessionsNoResults: View {
    /// 該当なしの見出しと説明を描画します。
    ///
    /// 責務: 絞り込み結果が空であることを説明付きの空表示へ配置します。
    var body: some View {
        ContentUnavailableView("history.filter.empty", systemImage: "magnifyingglass", description: Text("history.filter.empty.body"))
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
#endif
