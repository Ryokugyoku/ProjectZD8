#if os(iOS)
import SwiftUI

/// 履歴が存在しないことを示す表示です。
struct IOSConnectionHistoryEmptyState: View {
    /// 空の状態の見出しと説明を描画します。
    ///
    /// 責務: 履歴が無いことを説明付きの空表示へ配置します。
    var body: some View {
        ContentUnavailableView("history.empty.title", systemImage: "road.lanes", description: Text("history.empty.body"))
            .padding(30).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
#endif
