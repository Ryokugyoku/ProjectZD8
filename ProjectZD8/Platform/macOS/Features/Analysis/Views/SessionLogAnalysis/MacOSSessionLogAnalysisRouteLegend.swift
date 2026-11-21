#if os(macOS)
import SwiftUI

/// macOS の解析の「ルート」の表示で、線の色の凡例(色見本と範囲の文字)を横に折り返して並べます。
struct MacOSSessionLogAnalysisRouteLegend: View {
    /// 凡例の項目(表示順)です。
    let entries: [RouteAnalysisLegendEntry]
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 凡例を描画します。
    ///
    /// 責務: 見出しの下に、色見本と文字の組を幅に合わせて折り返して並べます。項目が無ければ何も描きません。
    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: MacOSRouteAnalysisMetrics.legendSpacing * scale) {
                Text("analysis.route.legend.title")
                    .font(.system(size: MacOSRouteAnalysisMetrics.noticeFontSize * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: MacOSRouteAnalysisMetrics.legendSpacing * scale) {
                    ForEach(entries) { entry in
                        item(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 幅に合わせて列の数が変わる格子の列です。
    private var columns: [GridItem] {
        let spacing = MacOSRouteAnalysisMetrics.legendSpacing * scale
        return [GridItem(.adaptive(minimum: MacOSRouteAnalysisMetrics.legendItemMinWidth * scale), spacing: spacing, alignment: .leading)]
    }

    /// 値なしの色見本の破線の描き方です。
    private var dashedStroke: StrokeStyle {
        StrokeStyle(
            lineWidth: MacOSRouteAnalysisMetrics.legendSwatchHeight * scale / 2,
            dash: MacOSRouteAnalysisMetrics.legendSwatchDashPattern.map { $0 * scale }
        )
    }

    /// 凡例の1項目を作ります。
    ///
    /// 責務: 分類の色見本(値なしは破線)と範囲の文字を横に並べます。
    /// - Parameter entry: 凡例の項目。
    /// - Returns: 項目の View。
    private func item(_ entry: RouteAnalysisLegendEntry) -> some View {
        HStack(spacing: MacOSRouteAnalysisMetrics.legendSpacing * scale) {
            swatch(entry.category)
            Text(entry.text)
                .font(.system(size: MacOSRouteAnalysisMetrics.noticeFontSize * scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// 分類の色見本を作ります。
    ///
    /// 責務: 破線の分類は線の色の破線、それ以外は塗りつぶした角丸の帯を描きます。
    /// - Parameter category: 色の分類。
    /// - Returns: 色見本の View。
    private func swatch(_ category: RouteAnalysisColorCategory) -> some View {
        Group {
            if category.isDashed {
                Capsule().stroke(category.color, style: dashedStroke)
            } else {
                Capsule().fill(category.color)
            }
        }
        .frame(width: MacOSRouteAnalysisMetrics.legendSwatchWidth * scale, height: MacOSRouteAnalysisMetrics.legendSwatchHeight * scale)
        .accessibilityHidden(true)
    }
}
#endif
