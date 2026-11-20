#if os(iOS)
import SwiftUI

/// 接続履歴の集計値を短い見出し付きで示す要約ピルです。履歴一覧と車両別一覧で使います。
struct IOSConnectionHistorySummaryPill: View {
    /// 表示値です。
    let value: String
    /// 値の意味を示すローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 値の表示色です。
    let color: Color

    /// 値と見出しを横に並べたピルを描画します。
    ///
    /// 責務: 1件の集計値を短い見出し付き要約へ配置します。
    var body: some View {
        HStack(spacing: 7) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(titleKey).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
            .padding(.horizontal, 13).padding(.vertical, 9).background(Color.primary.opacity(0.055), in: Capsule())
    }
}
#endif
