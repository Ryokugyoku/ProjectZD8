#if os(iOS)
import SwiftUI

/// iPhone の解析の「ルート」の表示で、線の色の凡例(色見本と範囲の文字)を横に折り返して並べます。
struct IOSSessionLogAnalysisRouteLegend: View {
    /// 凡例の項目(表示順)です。
    let entries: [RouteAnalysisLegendEntry]

    /// 凡例を描画します。
    ///
    /// 責務: 見出しの下に、色見本と文字の組を幅に合わせて折り返して並べます。項目が無ければ何も描きません。
    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: IOSRouteAnalysisMetrics.legendSpacing) {
                Text("analysis.route.legend.title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: IOSRouteAnalysisMetrics.legendSpacing) {
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
        [GridItem(.adaptive(minimum: IOSRouteAnalysisMetrics.legendItemMinWidth), spacing: IOSRouteAnalysisMetrics.legendSpacing, alignment: .leading)]
    }

    /// 凡例の1項目を作ります。
    ///
    /// 責務: 分類の色見本(値なしは破線)と範囲の文字を横に並べます。
    /// - Parameter entry: 凡例の項目。
    /// - Returns: 項目の View。
    private func item(_ entry: RouteAnalysisLegendEntry) -> some View {
        HStack(spacing: IOSRouteAnalysisMetrics.legendSpacing) {
            swatch(entry.category)
            Text(entry.text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// 値なしの色見本の破線の描き方です。
    private var dashedStroke: StrokeStyle {
        StrokeStyle(lineWidth: IOSRouteAnalysisMetrics.legendSwatchHeight / 2, dash: IOSRouteAnalysisMetrics.legendSwatchDashPattern)
    }

    /// 分類の色見本を作ります。
    ///
    /// 責務: 破線の分類は線の色の破線、それ以外は塗りつぶした角丸の帯を描きます。
    /// - Parameter category: 色の分類。
    /// - Returns: 色見本の View。
    @ViewBuilder private func swatch(_ category: RouteAnalysisColorCategory) -> some View {
        let shape = Capsule()
        Group {
            if category.isDashed {
                shape.stroke(category.color, style: dashedStroke)
            } else {
                shape.fill(category.color)
            }
        }
        .frame(width: IOSRouteAnalysisMetrics.legendSwatchWidth, height: IOSRouteAnalysisMetrics.legendSwatchHeight)
        .accessibilityHidden(true)
    }
}
#endif
