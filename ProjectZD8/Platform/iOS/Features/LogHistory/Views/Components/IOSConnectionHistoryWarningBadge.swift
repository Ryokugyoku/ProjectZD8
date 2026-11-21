#if os(iOS)
import SwiftUI

/// 中断件数を色とシンボルで示す注意バッジです。履歴一覧と車両別一覧で使います。
struct IOSConnectionHistoryWarningBadge: View {
    /// 表示する中断件数です。
    let count: Int

    /// 警告アイコンと件数を並べたバッジを描画します。
    ///
    /// 責務: 1件の中断件数を色とシンボルを併用した警告へ配置します。
    var body: some View {
        HStack(spacing: 4) {
            WarningTriangleIcon(size: 11)
            Text("\(count)")
        }
            .font(.caption.weight(.bold)).foregroundStyle(.orange)
            .padding(.horizontal, 9).padding(.vertical, 6).background(.orange.opacity(0.11), in: Capsule())
            .accessibilityLabel(Text("history.warning.interrupted"))
            .accessibilityValue(Text(count, format: .number))
    }
}
#endif
