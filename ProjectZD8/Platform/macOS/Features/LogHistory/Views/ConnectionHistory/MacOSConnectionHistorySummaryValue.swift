#if os(macOS)
import SwiftUI

/// ヒーローカードに並べる大きな数字と見出しの集計表示です。
struct MacOSConnectionHistorySummaryValue: View {
    /// 表示値です。
    let value: String
    /// 値の意味を示すローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 値の表示色です。
    let color: Color
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 値と見出しを右揃えで縦に並べます。
    ///
    /// 責務: 1件の集計値をmacOS用の要約表示へ変換します。
    var body: some View {
        VStack(alignment: .trailing, spacing: 2 * scale) {
            Text(value).font(.system(size: 24 * scale, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(color)
            Text(titleKey).font(.system(size: 9.5 * scale, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 78 * scale)
    }
}
#endif
