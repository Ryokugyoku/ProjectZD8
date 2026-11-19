#if os(macOS)
import SwiftUI

/// PID分類を代表値付きで示し、押すとその分類の一覧へ切り替えるチップです。
struct MacOSLiveTelemetryPanelCategoryButton: View {
    /// 表示するPID分類です。
    let category: OBDPIDCategory
    /// 分類の代表値です。分類にサンプルがなければ `nil` です。
    let representative: OBDPIDSample?
    /// この分類を選択中かどうかです。
    let isSelected: Bool
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// この分類の選択を通知するクロージャです。
    let onSelect: () -> Void

    /// 数値の整形に使う現在のロケールです。
    @Environment(\.locale) private var locale

    /// 記号、分類名、代表値を横に並べたカプセル形のボタンを描画します。
    ///
    /// 責務: 1件のPID分類を選択状態付きの分類チップへ描画します。
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9 * scale) {
                Image(systemName: LiveTelemetrySampleSymbols.categorySymbol(for: category))
                Text(LocalizedStringKey(category.nameKey))
                    .fontWeight(.semibold)
                if let representative {
                    Text(verbatim: LiveTelemetrySampleFormatter().detailValueWithUnitText(representative, locale: locale))
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .opacity(0.8)
                }
            }
            .font(.system(size: 11 * scale, design: .rounded))
            .padding(.horizontal, 14 * scale)
            .frame(minHeight: 44 * scale)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: Capsule())
            .overlay { Capsule().stroke(isSelected ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.07)) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
