#if os(macOS)
import SwiftUI

/// 車両カードと車両別ヘッダーに並べる短い集計列です。
struct MacOSConnectionHistoryMetric: View {
    /// 表示値です。
    let value: String
    /// 値の意味を示すローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 値と見出しを縦に並べます。
    ///
    /// 責務: 1件の文字列集計値を値と見出しを含む集計列へ変換します。
    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(value).font(.system(size: 13 * scale, weight: .bold, design: .rounded).monospacedDigit())
            Text(titleKey).font(.system(size: 8.5 * scale, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(minWidth: 74 * scale, alignment: .leading)
    }
}
#endif
