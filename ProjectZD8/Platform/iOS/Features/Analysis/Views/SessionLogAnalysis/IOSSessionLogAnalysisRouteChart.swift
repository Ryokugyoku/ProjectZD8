#if os(iOS)
import Charts
import SwiftUI

/// iPhone の解析の「ルート」の表示で、指標または標高の推移を折れ線で描き、なぞった時刻を送出します。
struct IOSSessionLogAnalysisRouteChart: View {
    /// グラフの見出しのローカライズキーです。
    let titleKey: String
    /// グラフの説明のローカライズキーです。
    let subtitleKey: String
    /// 描く系列です。
    let series: RouteAnalysisChartSeries
    /// グラフの高さです。
    let height: CGFloat
    /// 強調する時刻の範囲です。
    let highlightedTimeRanges: [ClosedRange<Date>]
    /// 選んでいる時刻です。選んでいない時は `nil` です。
    let selectedDate: Date?
    /// UI テストで使う識別子です。
    let accessibilityIdentifier: String
    /// なぞった時刻(離すと `nil`)を送出します。
    let onSelect: (Date?) -> Void

    /// 見出し・説明・グラフを描画します。
    ///
    /// 責務: 強調の範囲・切れ目ごとの線・選んだ時刻の縦線を重ね、なぞった時刻を送出するグラフを描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRouteAnalysisMetrics.chartSpacing) {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline.weight(.semibold))
            Text(LocalizedStringKey(subtitleKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            chart
                .chartXSelection(value: selection)
                .chartYAxisLabel(series.unit)
                .frame(height: height)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    /// 強調の範囲・線・選んだ時刻の縦線を重ねたグラフです。
    private var chart: some View {
        Chart {
            ForEach(Array(highlightedTimeRanges.enumerated()), id: \.offset) { _, range in
                RectangleMark(xStart: .value(timeLabel, range.lowerBound), xEnd: .value(timeLabel, range.upperBound))
                    .foregroundStyle(Color.cyan.opacity(IOSRouteAnalysisMetrics.highlightOpacity))
            }
            ForEach(series.points) { point in
                LineMark(
                    x: .value(timeLabel, point.date),
                    y: .value(valueLabel, point.value),
                    series: .value(lineLabel, point.lineID)
                )
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: IOSRouteAnalysisMetrics.chartLineWidth))
                .interpolationMethod(.linear)
            }
            if let selectedDate {
                RuleMark(x: .value(timeLabel, selectedDate))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: IOSRouteAnalysisMetrics.selectionRuleWidth))
            }
        }
    }

    /// グラフの選択と、時刻の送出をつなぐ値です。
    ///
    /// 責務: 表示する選択は状態の時刻から読み、グラフで変わった時刻はそのまま送出します。
    private var selection: Binding<Date?> {
        Binding(get: { selectedDate }, set: { onSelect($0) })
    }

    /// 横軸の名前です。
    private var timeLabel: String {
        String(localized: "analysis.chart.time")
    }

    /// 縦軸の名前です。
    private var valueLabel: String {
        String(localized: "analysis.chart.value")
    }

    /// 線の切れ目ごとの系列の名前です(画面には出しません)。
    private var lineLabel: String {
        "line"
    }
}
#endif
