#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、1件の学習準備の指標をカードとして表示します。
struct MacOSConnectionSessionDetailStatusCard: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 指標の見出しのローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 強調表示する値です。
    let value: String
    /// 値を補足する短い文字列です。
    let caption: String
    /// 指標の概念を示す SF Symbol です。
    let systemImage: String
    /// 指標のアクセント色です。
    let color: Color

    /// 見出し、値、補足を縦に並べた、同じ高さで並べられるカードを描画します。
    ///
    /// 責務: 1件の指標を見出し、値、補足、アイコンを持つ macOS カードへ変換します。
    var body: some View {
        VStack(alignment: .leading, spacing: 13 * scale) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(color)
                Text(titleKey).font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 9.5 * scale, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, minHeight: 132 * scale, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 21 * scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 21 * scale, style: .continuous).stroke(color.opacity(0.15)) }
    }
}
#endif
