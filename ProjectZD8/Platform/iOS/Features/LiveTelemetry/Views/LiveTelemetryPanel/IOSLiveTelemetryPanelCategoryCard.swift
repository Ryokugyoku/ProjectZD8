#if os(iOS)
import SwiftUI

/// 1分類の収録数と代表値を示す、詳細画面への遷移カードです。
struct IOSLiveTelemetryPanelCategoryCard: View {
    /// 表示するPID分類です。
    let category: OBDPIDCategory
    /// 分類に含まれる応答済みPIDの数です。
    let count: Int
    /// 分類の代表値です。分類が空なら `nil` です。
    let representative: OBDPIDSample?

    /// 数値の整形に使う現在のロケールです。
    @Environment(\.locale) private var locale

    /// 分類の記号、名称、収録数、代表値、遷移の印を横に並べます。
    ///
    /// 責務: 1件のPID分類を代表値付きの横長カードへ描画します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IOSLiveTelemetryPanelMetrics.categoryCardCornerRadius, style: .continuous)
        HStack(spacing: 14) {
            categoryIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(category.nameKey)).font(.headline)
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let representative {
                representativeValue(representative)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(IOSLiveTelemetryPanelMetrics.categoryCardPadding)
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(Color.primary.opacity(0.07)) }
        .accessibilityElement(children: .combine)
    }

    /// 分類を表す記号を角丸の枠に入れた表示です。
    private var categoryIcon: some View {
        Image(systemName: LiveTelemetrySampleSymbols.categorySymbol(for: category))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: IOSLiveTelemetryPanelMetrics.categoryIconSize, height: IOSLiveTelemetryPanelMetrics.categoryIconSize)
            .background(
                Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: IOSLiveTelemetryPanelMetrics.categoryIconCornerRadius, style: .continuous)
            )
    }

    /// 代表値の数値と単位を右寄せで示します。
    ///
    /// 責務: 1件の代表サンプルを数値と単位の2行表示へ変換します。
    /// - Parameter sample: 分類の代表サンプル。
    /// - Returns: 数値と単位の縦並び。
    private func representativeValue(_ sample: OBDPIDSample) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: LiveTelemetrySampleFormatter().primaryValueText(sample, locale: locale))
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
            Text(verbatim: sample.unit)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
#endif
