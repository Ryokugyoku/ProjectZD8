#if os(macOS)
import SwiftUI

/// 中断件数を示す注意バッジです。
struct MacOSConnectionHistoryWarningBadge: View {
    /// 表示する中断件数です。
    let count: Int
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 警告三角と件数をカプセル内に並べます。
    ///
    /// 責務: 1件の中断件数を色とシンボルを併用した警告へ変換します。
    var body: some View {
        HStack(spacing: 4 * scale) {
            WarningTriangleIcon(size: 10 * scale)
            Text("\(count)")
        }
            .font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(.orange)
            .padding(.horizontal, 9 * scale).padding(.vertical, 6 * scale).background(.orange.opacity(0.11), in: Capsule())
            .accessibilityLabel(Text("history.warning.interrupted"))
            .accessibilityValue(Text(count, format: .number))
    }
}
#endif
