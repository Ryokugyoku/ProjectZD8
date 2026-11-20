#if os(iOS)
import Charts
import SwiftUI

/// iPhoneのセッション解析で選択PIDの時間変化を折れ線グラフで示すカードです。
struct IOSSessionLogAnalysisTrendCard: View {
    /// 選べるPID系列です。
    let seriesList: [SessionPIDSeries]
    /// 折れ線グラフへ表示するPIDの選択です。
    @Binding var selectedSeriesID: OBDPIDRequest?
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 選択PIDの折れ線グラフ、または系列が無い時の案内を表示します。
    ///
    /// 責務: 選択中または先頭のPID系列を、選択メニュー・読解ガイド・折れ線グラフのカードへ変換します。
    var body: some View {
        if let series = selectedSeries {
            IOSSessionLogAnalysisCard(title: "analysis.trend.title", subtitle: "analysis.trend.subtitle") {
                Picker("analysis.trend.pid", selection: $selectedSeriesID) {
                    ForEach(seriesList) { item in
                        Text(formatter.seriesName(item)).tag(Optional(item.id))
                    }
                }
                trendGuide(series)
                Chart(series.points) { point in
                    LineMark(
                        x: .value(String(localized: "analysis.chart.time"), point.observedAt),
                        y: .value(String(localized: "analysis.chart.value"), point.value)
                    )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.linear)
                }
                .chartYAxisLabel(series.unit)
                .frame(height: 250)
            }
        } else {
            ContentUnavailableView(
                "analysis.trend.empty.title",
                systemImage: "chart.xyaxis.line",
                description: Text("analysis.trend.empty.body")
            )
        }
    }

    /// 現在選択中または先頭の折れ線系列です。
    private var selectedSeries: SessionPIDSeries? {
        seriesList.first(where: { $0.id == selectedSeriesID }) ?? seriesList.first
    }

    /// 選択PIDの識別子、意味、統計値、解釈上の注意を表示します。
    ///
    /// 責務: 1件のPID系列を折れ線グラフの読解ガイドへ変換します。
    /// - Parameter series: 説明するPID系列。
    /// - Returns: PIDの来歴と観測可能範囲を示す案内表示。
    private func trendGuide(_ series: SessionPIDSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(formatter.pidLabel(service: series.id.service, pid: series.id.pid))
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.tint)
                if let modelCode = series.vehicleModelCode {
                    VehicleModelBadge(modelCode: modelCode)
                        .scaleEffect(0.68)
                        .frame(width: 26, height: 26)
                }
            }
            Text(String(localized: String.LocalizationValue(series.interpretationKey)))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                statistic("analysis.trend.minimum", value: series.minimumValue, unit: series.unit)
                statistic("analysis.trend.average", value: series.averageValue, unit: series.unit)
                statistic("analysis.trend.maximum", value: series.maximumValue, unit: series.unit)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 統計名と値を縦に並べて表示します。
    ///
    /// 責務: 1件のPID統計値を折れ線ガイド内の短い表示へ変換します。
    /// - Parameters:
    ///   - key: 最小・平均・最大の見出し。
    ///   - value: 表示する数値。
    ///   - unit: PID定義の単位。
    /// - Returns: 見出し付き統計値。
    private func statistic(_ key: LocalizedStringKey, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption2).foregroundStyle(.secondary)
            Text(formatter.measurementText(value, unit: unit)).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}
#endif
