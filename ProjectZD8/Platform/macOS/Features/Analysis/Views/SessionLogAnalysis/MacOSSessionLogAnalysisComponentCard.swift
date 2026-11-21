#if os(macOS)
import SwiftUI

/// macOSのセッション解析で取得できたPIDを部品・系統別に示すカードです。
struct MacOSSessionLogAnalysisComponentCard: View {
    /// 部品・系統別の観察結果です。
    let insights: [SessionComponentInsight]
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 部品・系統別の観察結果または空の案内を表示します。
    ///
    /// 責務: 部品・系統別の観察結果を、見出し・PID名・説明・統計を持つ小型カードの格子へ変換します。
    var body: some View {
        MacOSSessionLogAnalysisCard(title: "analysis.components.title", subtitle: "analysis.components.subtitle", metrics: metrics) {
            if insights.isEmpty {
                Text("analysis.components.empty").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300 * metrics.scale), spacing: 12 * metrics.scale)],
                    spacing: 12 * metrics.scale
                ) {
                    ForEach(insights) { insight in
                        tile(insight)
                    }
                }
            }
        }
    }

    /// 1件の部品・系統の観察結果を小型カードで表示します。
    ///
    /// 責務: 1件の観察結果を見出し・PID名・型式・説明・統計の小型カードへ変換します。
    /// - Parameter insight: 表示する観察結果。
    /// - Returns: 格子に並べる小型カード。
    private func tile(_ insight: SessionComponentInsight) -> some View {
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            Label(
                LocalizedStringKey(formatter.componentTitleKey(insight.component)),
                systemImage: formatter.componentSymbol(insight.component)
            )
            .font(.system(size: 13 * metrics.scale, weight: .semibold))
            HStack(spacing: 8 * metrics.scale) {
                Text(formatter.seriesName(insight.series)).font(.system(size: 12 * metrics.scale, weight: .semibold))
                if let modelCode = insight.series.vehicleModelCode {
                    VehicleModelBadge(modelCode: modelCode)
                }
            }
            Text(LocalizedStringKey(formatter.componentDescriptionKey(insight.component)))
                .font(.system(size: 10 * metrics.scale))
                .foregroundStyle(.secondary)
            Text(formatter.statisticsText(insight.series))
                .font(.system(size: 10 * metrics.scale, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(14 * metrics.scale)
        .frame(maxWidth: .infinity, minHeight: 132 * metrics.scale, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
    }
}
#endif
