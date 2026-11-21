#if os(iOS)
import SwiftUI

/// iPhoneのセッション解析で取得できたPIDを部品・系統別に示すカードです。
struct IOSSessionLogAnalysisComponentCard: View {
    /// 部品・系統別の観察結果です。
    let insights: [SessionComponentInsight]
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 部品・系統別の観察結果または空の案内を表示します。
    ///
    /// 責務: 部品・系統別の観察結果を、見出し・PID名・説明・統計の一覧へ変換します。
    var body: some View {
        IOSSessionLogAnalysisCard(title: "analysis.components.title", subtitle: "analysis.components.subtitle") {
            if insights.isEmpty {
                Text("analysis.components.empty").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    row(insight)
                }
            }
        }
    }

    /// 1件の部品・系統の観察結果を表示します。
    ///
    /// 責務: 1件の観察結果を見出し・PID名・型式・説明・統計の縦並びへ変換します。
    /// - Parameter insight: 表示する観察結果。
    /// - Returns: 部品カード内の1行。
    private func row(_ insight: SessionComponentInsight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                LocalizedStringKey(formatter.componentTitleKey(insight.component)),
                systemImage: formatter.componentSymbol(insight.component)
            )
            .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Text(formatter.seriesName(insight.series)).font(.caption.weight(.semibold))
                if let modelCode = insight.series.vehicleModelCode {
                    VehicleModelBadge(modelCode: modelCode)
                        .scaleEffect(0.68)
                        .frame(width: 26, height: 26)
                }
            }
            Text(LocalizedStringKey(formatter.componentDescriptionKey(insight.component))).font(.caption).foregroundStyle(.secondary)
            Text(formatter.statisticsText(insight.series)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}
#endif
