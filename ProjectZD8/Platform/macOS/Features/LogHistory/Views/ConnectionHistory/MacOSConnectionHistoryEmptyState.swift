#if os(macOS)
import SwiftUI

/// 履歴が存在しないことを示す空状態です。
struct MacOSConnectionHistoryEmptyState: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 空状態の説明を描画します。
    ///
    /// 責務: 履歴0件を説明付きの空状態表示へ配置します。
    var body: some View {
        ContentUnavailableView("history.empty.title", systemImage: "road.lanes", description: Text("history.empty.body"))
            .padding(38 * scale).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
    }
}
#endif
